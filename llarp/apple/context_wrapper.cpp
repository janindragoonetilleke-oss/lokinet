// Stubbed-out Apple context wrapper.
//
// The original implementation relied on a significantly older llarp::Config and llarp::Context API
// that no longer exists (e.g. Config::load, Config::network.if_addr, Context::Configure,
// Context::Setup, Context::Run, llarp::RuntimeOptions, etc.).
//
// These C-linkage functions are only called from the macOS Network Extension (PacketTunnelProvider)
// and are unused by the CLI daemon.  They are stubbed here so that the daemon can link without
// requiring a full rewrite of the Network Extension integration layer.

#include "context_wrapper.h"

#include "context.hpp"
#include "vpn_interface.hpp"

#include <llarp/config/config.hpp>
#include <llarp/constants/apple.hpp>
#include <llarp/net/ip_packet.hpp>
#include <llarp/util/logging.hpp>

#include <cassert>
#include <cstdint>
#include <cstring>

namespace
{
    static auto logcat = oxen::log::Cat("apple.ctx_wrapper");
}

extern "C" const uint16_t dns_trampoline_port = llarp::apple::dns_trampoline_port;

void* llarp_apple_init(llarp_apple_config*)
{
    oxen::log::error(logcat, "llarp_apple_init is not implemented in this build");
    return nullptr;
}

int llarp_apple_start(void*, void*)
{
    oxen::log::error(logcat, "llarp_apple_start is not implemented in this build");
    return -1;
}

uv_loop_t* llarp_apple_get_uv_loop(void*)
{
    oxen::log::error(logcat, "llarp_apple_get_uv_loop is not implemented in this build");
    return nullptr;
}

int llarp_apple_incoming(void*, const llarp_incoming_packet*, size_t)
{
    oxen::log::error(logcat, "llarp_apple_incoming is not implemented in this build");
    return -1;
}

void llarp_apple_shutdown(void*)
{
    oxen::log::error(logcat, "llarp_apple_shutdown is not implemented in this build");
}
