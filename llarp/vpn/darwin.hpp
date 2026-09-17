#pragma once

#include "common.hpp"
#include "platform.hpp"

#include <llarp.hpp>
#include <llarp/router/router.hpp>
#include <llarp/util/str.hpp>

#include <arpa/inet.h>
#include <fcntl.h>
#include <net/if.h>
#include <net/if_utun.h>
#include <oxenc/endian.h>
#include <sys/ioctl.h>
#include <sys/kern_control.h>
#include <sys/socket.h>
#include <sys/sys_domain.h>
#include <sys/types.h>
#include <sys/uio.h>
#include <unistd.h>

#include <cstdlib>
#include <cstring>
#include <functional>
#include <list>
#include <stdexcept>

namespace llarp::vpn
{
    static auto logcat = log::Cat("vpn.darwin");

    struct call_on_destroy
    {
        std::function<void()> f;
        ~call_on_destroy()
        {
            if (f)
                f();
        }
        void disarm() { f = nullptr; }
    };

    class DarwinInterface : public NetworkInterface
    {
        const int _fd;

      public:
        DarwinInterface(InterfaceInfo info)
            : NetworkInterface{std::move(info)}, _fd{::socket(PF_SYSTEM, SOCK_DGRAM, SYSPROTO_CONTROL)}
        {
            if (_fd == -1)
                throw std::runtime_error{"cannot open control socket: {}"_format(strerror(errno))};

            call_on_destroy fd_abort{[fd = _fd] { close(fd); }};

            if (fcntl(_fd, F_SETFL, O_NONBLOCK) == -1)
                throw std::runtime_error{
                    "Failed to set `O_NONBLOCK` on Darwin interface FD: {}"_format(strerror(errno))};

            ctl_info cinfo{};
            std::strncpy(cinfo.ctl_name, UTUN_CONTROL_NAME, sizeof(cinfo.ctl_name) - 1);
            if (::ioctl(_fd, CTLIOCGINFO, &cinfo) < 0)
                throw std::runtime_error{"ioctl CTLIOCGINFO call failed: {}"_format(strerror(errno))};

            sockaddr_ctl addr{};
            addr.sc_len = sizeof(addr);
            addr.sc_family = AF_SYSTEM;
            addr.ss_sysaddr = AF_SYS_CONTROL;
            addr.sc_id = cinfo.ctl_id;
            addr.sc_unit = 0;  // 0 instructs kernel to dynamically allocate next utunX unit

            if (connect(_fd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) < 0)
                throw std::runtime_error{"cannot connect to control socket: {}"_format(strerror(errno))};

            char name[IFNAMSIZ + 1]{};
            socklen_t namesz = sizeof(name);
            if (getsockopt(_fd, SYSPROTO_CONTROL, UTUN_OPT_IFNAME, name, &namesz) < 0)
                throw std::runtime_error{"cannot query interface name: {}"_format(strerror(errno))};

            _info.ifname = name;
            _info.index = if_nametoindex(name);

            log::debug(logcat, "Allocated Darwin utun interface '{}' (index {})", _info.ifname, _info.index);

            if (_info.addrs.empty())
                throw std::runtime_error{"Cannot set up a TUN interface with no addresses!"};

            std::list<std::string> addr_strings;
            for (const auto& ifaddr : _info.addrs)
            {
                if (auto* n4 = std::get_if<ipv4_net>(&ifaddr))
                {
                    addr_strings.push_back(n4->to_string());
                    std::string ip_str = n4->ip.to_string();

                    uint32_t netmask_int = n4->mask ? (~uint32_t(0) << (32 - n4->mask)) : 0;
                    ipv4 netmask_ip{netmask_int};
                    std::string netmask_str = netmask_ip.to_string();

                    // On macOS, utun point-to-point requires:
                    // /sbin/ifconfig <ifname> <local_ip> <dest_ip> mtu 1500 netmask <mask> up
                    std::string ifconfig_cmd = fmt::format(
                        "/sbin/ifconfig {} {} {} mtu 1500 netmask {} up",
                        _info.ifname,
                        ip_str,
                        ip_str,
                        netmask_str);
                    log::debug(logcat, "Configuring utun IPv4: {}", ifconfig_cmd);
                    if (std::system(ifconfig_cmd.c_str()) != 0)
                        log::warning(logcat, "ifconfig command failed: {}", ifconfig_cmd);

                    // Add route for the network subnet to point into this interface
                    std::string route_cmd = fmt::format(
                        "/sbin/route add -net {}/{} -interface {} >/dev/null 2>&1",
                        n4->ip.to_base(n4->mask).to_string(),
                        n4->mask,
                        _info.ifname);
                    log::debug(logcat, "Adding subnet route: {}", route_cmd);
                    std::system(route_cmd.c_str());
                }
                else
                {
                    auto& n6 = std::get<ipv6_net>(ifaddr);
                    addr_strings.push_back(n6.to_string());
                    std::string ifconfig_cmd = fmt::format(
                        "/sbin/ifconfig {} inet6 {}/{} up",
                        _info.ifname,
                        n6.ip.to_string(),
                        n6.mask);
                    log::debug(logcat, "Configuring utun IPv6: {}", ifconfig_cmd);
                    if (std::system(ifconfig_cmd.c_str()) != 0)
                        log::warning(logcat, "ifconfig command failed: {}", ifconfig_cmd);
                }
            }

            fd_abort.disarm();
            log::info(logcat, "Darwin utun device {} now up with address(es): {}", _info.ifname, fmt::join(addr_strings, ", "));
        }

        ~DarwinInterface() override
        {
            ::close(_fd);
        }

        int PollFD() const override { return _fd; }

        IPPacket read_next_packet() override
        {
            // macOS utun prepends a 4-byte address family in network byte order
            uint32_t af = 0;
            std::vector<std::byte> buf;
            buf.resize(MAX_PACKET_SIZE);

            struct iovec iov[2];
            iov[0].iov_base = &af;
            iov[0].iov_len = sizeof(af);
            iov[1].iov_base = buf.data();
            iov[1].iov_len = buf.capacity();

            const auto sz = readv(_fd, iov, 2);
            if (sz < static_cast<ssize_t>(sizeof(af)))
            {
                if (sz < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
                {
                    errno = 0;
                    return IPPacket{};
                }
                if (sz < 0)
                    throw std::error_code{errno, std::system_category()};
                return IPPacket{};
            }

            buf.resize(sz - sizeof(af));
            return IPPacket{std::move(buf)};
        }

        bool write_packet(IPPacket pkt) override
        {
            // macOS utun requires a 4-byte address family prefix in network byte order
            uint32_t af = htonl(pkt.is_ipv6() ? AF_INET6 : AF_INET);

            struct iovec iov[2];
            iov[0].iov_base = &af;
            iov[0].iov_len = sizeof(af);
            iov[1].iov_base = pkt.data();
            iov[1].iov_len = pkt.size();

            const auto sz = writev(_fd, iov, 2);
            if (sz <= 0)
                return false;
            return sz == static_cast<ssize_t>(sizeof(af) + pkt.size());
        }
    };

    class DarwinRouteManager : public AbstractRouteManager
    {
      public:
        DarwinRouteManager() = default;
        ~DarwinRouteManager() override = default;

        void add_route(ipv4 ip, ipv4 gateway) override
        {
            auto cmd = fmt::format(
                "/sbin/route add -host {} {} >/dev/null 2>&1",
                ip.to_string(),
                gateway.to_string());
            std::system(cmd.c_str());
        }

        void add_route(ipv6 ip, ipv6 gateway) override
        {
            auto cmd = fmt::format(
                "/sbin/route add -inet6 -host {} {} >/dev/null 2>&1",
                ip.to_string(),
                gateway.to_string());
            std::system(cmd.c_str());
        }

        void delete_route(ipv4 ip, ipv4 gateway) override
        {
            auto cmd = fmt::format(
                "/sbin/route delete -host {} {} >/dev/null 2>&1",
                ip.to_string(),
                gateway.to_string());
            std::system(cmd.c_str());
        }

        void delete_route(ipv6 ip, ipv6 gateway) override
        {
            auto cmd = fmt::format(
                "/sbin/route delete -inet6 -host {} {} >/dev/null 2>&1",
                ip.to_string(),
                gateway.to_string());
            std::system(cmd.c_str());
        }

        void add_default_route_via_interface(NetworkInterface& vpn) override
        {
            auto cmd = fmt::format(
                "/sbin/route add default -interface {} >/dev/null 2>&1",
                vpn.interface_info().ifname);
            std::system(cmd.c_str());
        }

        void delete_default_route_via_interface(NetworkInterface& vpn) override
        {
            auto cmd = fmt::format(
                "/sbin/route delete default -interface {} >/dev/null 2>&1",
                vpn.interface_info().ifname);
            std::system(cmd.c_str());
        }

        void add_route_via_interface(NetworkInterface& vpn, ipv4_range range) override
        {
            auto cmd = fmt::format(
                "/sbin/route add -net {}/{} -interface {} >/dev/null 2>&1",
                range.ip.to_string(),
                range.mask,
                vpn.interface_info().ifname);
            std::system(cmd.c_str());
        }

        void add_route_via_interface(NetworkInterface& vpn, ipv6_range range) override
        {
            auto cmd = fmt::format(
                "/sbin/route add -inet6 -net {}/{} -interface {} >/dev/null 2>&1",
                range.ip.to_string(),
                range.mask,
                vpn.interface_info().ifname);
            std::system(cmd.c_str());
        }

        void delete_route_via_interface(NetworkInterface& vpn, ipv4_range range) override
        {
            auto cmd = fmt::format(
                "/sbin/route delete -net {}/{} -interface {} >/dev/null 2>&1",
                range.ip.to_string(),
                range.mask,
                vpn.interface_info().ifname);
            std::system(cmd.c_str());
        }

        void delete_route_via_interface(NetworkInterface& vpn, ipv6_range range) override
        {
            auto cmd = fmt::format(
                "/sbin/route delete -inet6 -net {}/{} -interface {} >/dev/null 2>&1",
                range.ip.to_string(),
                range.mask,
                vpn.interface_info().ifname);
            std::system(cmd.c_str());
        }

        std::vector<quic::Address> get_non_interface_gateways(NetworkInterface& /*vpn*/) override
        {
            return {};
        }
    };

    class DarwinPlatform : public Platform
    {
        DarwinRouteManager _routeManager{};

      public:
        std::shared_ptr<NetworkInterface> obtain_interface(InterfaceInfo info, Router*) override
        {
            return std::make_shared<DarwinInterface>(std::move(info));
        }

        AbstractRouteManager& RouteManager() override { return _routeManager; }
    };

}  // namespace llarp::vpn
