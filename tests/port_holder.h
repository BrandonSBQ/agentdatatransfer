// test/support/port_holder.h
//
// RAII helper for tests that need a TCP port to either (a) occupy so another
// listener can be observed failing to bind, or (b) hand off to a server under
// test on the same port.
//
// On POSIX we open a SOCK_STREAM socket, set SO_REUSEADDR (so the same port
// can be rebound immediately after we release it), bind to port 0, listen,
// and read the assigned port with getsockname.

#pragma once

#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>

#include <cstdint>
#include <stdexcept>
#include <utility>

namespace company_file_service {
namespace test {

class PortHolder {
public:
    // Picks a free loopback port and holds it until destruction.
    PortHolder() : PortHolder(/*preferred=*/0) {}

    // Binds a specific port; throws if it cannot. Useful when reproducing a
    // "port already in use" condition against a known port.
    explicit PortHolder(int preferred)
    {
        fd_ = ::socket(AF_INET, SOCK_STREAM, 0);
        if (fd_ < 0) {
            throw std::runtime_error("PortHolder: socket() failed");
        }

        const int one = 1;
        if (::setsockopt(fd_, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one)) < 0) {
            ::close(fd_);
            throw std::runtime_error("PortHolder: setsockopt(SO_REUSEADDR) failed");
        }

        sockaddr_in addr{};
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        addr.sin_port = htons(static_cast<std::uint16_t>(preferred));

        if (::bind(fd_, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) < 0) {
            ::close(fd_);
            throw std::runtime_error("PortHolder: bind() failed");
        }
        if (::listen(fd_, 16) < 0) {
            ::close(fd_);
            throw std::runtime_error("PortHolder: listen() failed");
        }

        socklen_t len = sizeof(addr);
        if (::getsockname(fd_, reinterpret_cast<sockaddr*>(&addr), &len) < 0) {
            ::close(fd_);
            throw std::runtime_error("PortHolder: getsockname() failed");
        }
        port_ = ntohs(addr.sin_port);
    }

    ~PortHolder()
    {
        if (fd_ >= 0) {
            ::close(fd_);
        }
    }

    PortHolder(const PortHolder&) = delete;
    PortHolder& operator=(const PortHolder&) = delete;
    PortHolder(PortHolder&&) = delete;
    PortHolder& operator=(PortHolder&&) = delete;

    int port() const noexcept { return port_; }

private:
    int fd_ = -1;
    int port_ = 0;
};

// Returns a port number that was free at the time of the call. The returned
// port is NOT held; rely on SO_REUSEADDR semantics in the caller. Use this
// when you want to start a server immediately and don't need to stage a
// conflict scenario.
inline int PickFreeLoopbackPort()
{
    PortHolder h;
    return h.port();
}

}  // namespace test
}  // namespace company_file_service
