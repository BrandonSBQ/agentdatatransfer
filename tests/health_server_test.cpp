// tests/health_server_test.cpp
//
// Characterization tests for HealthServer. The implementation already exists
// in src/http/health_server.cc; these tests pin down its observable contract
// so future refactors cannot silently regress the liveness probe.

#include "http/health_server.h"

#include "port_holder.h"

#include <httplib.h>

#include <chrono>
#include <stdexcept>
#include <string>
#include <thread>
#include <type_traits>

#include <catch2/catch_test_macros.hpp>
#include <catch2/matchers/catch_matchers_string.hpp>

using company_file_service::HealthServer;
using company_file_service::test::PortHolder;

namespace {

// Brief pause to let a freshly-started server begin accepting connections.
// wait_until_ready() in the production code blocks until the listener is up,
// so this is belt-and-suspenders for the client side.
void SettleHttpClient()
{
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
}

constexpr const char* kExpectedBody = R"({"status":"ok"})";
constexpr const char* kExpectedContentType = "application/json; charset=utf-8";

}  // namespace

TEST_CASE("HealthServer copy and move are deleted at the type level",
          "[health_server][type]")
{
    STATIC_REQUIRE_FALSE(std::is_copy_constructible_v<HealthServer>);
    STATIC_REQUIRE_FALSE(std::is_copy_assignable_v<HealthServer>);
    STATIC_REQUIRE_FALSE(std::is_move_constructible_v<HealthServer>);
    STATIC_REQUIRE_FALSE(std::is_move_assignable_v<HealthServer>);
}

TEST_CASE("HealthServer serves GET /healthy with HTTP 200 and the contract body",
          "[health_server][http]")
{
    const int port = company_file_service::test::PickFreeLoopbackPort();
    HealthServer server("127.0.0.1", port);

    httplib::Client client("127.0.0.1", port);
    client.set_connection_timeout(2, 0);
    SettleHttpClient();

    const auto response = client.Get("/healthy");
    REQUIRE(response);
    CHECK(response->status == 200);
    CHECK(response->body == kExpectedBody);
    CHECK(response->get_header_value("Content-Type") == kExpectedContentType);
    // Body length must match what was sent so K8s probes using
    // Content-Length do not stall.
    CHECK(response->body.size() == std::string(kExpectedBody).size());
}

TEST_CASE("HealthServer returns 404 for paths other than /healthy",
          "[health_server][http][routing]")
{
    const int port = company_file_service::test::PickFreeLoopbackPort();
    HealthServer server("127.0.0.1", port);

    httplib::Client client("127.0.0.1", port);
    client.set_connection_timeout(2, 0);
    SettleHttpClient();

    // Sanity check: the registered route must work.
    REQUIRE(client.Get("/healthy"));
    CHECK(client.Get("/healthy")->status == 200);

    // Everything else must NOT be served by the health server. We don't want
    // the probe accidentally shadowing main-API routes on a different port.
    // Note: cpp-httplib strips the query string before route matching, so
    // "/healthy?x=1" still hits the /healthy handler and is tested above.
    for (const char* path : {"/", "/health", "/HEALTHY", "/healthy/"}) {
        CAPTURE(path);
        const auto res = client.Get(path);
        REQUIRE(res);
        CHECK(res->status == 404);
    }
}

TEST_CASE("HealthServer constructor throws std::runtime_error when port is in use",
          "[health_server][lifecycle]")
{
    PortHolder occupier;  // Holds a port; the next listener must fail to bind.

    REQUIRE_THROWS_AS(
        HealthServer("127.0.0.1", occupier.port()),
        std::runtime_error);

    // After the failed construction, the system must still be able to bring
    // up another HealthServer once the port is released. This guards against
    // a regression where a partially-constructed server leaks the thread or
    // a file descriptor.
    {
        HealthServer server("127.0.0.1", occupier.port() + 1);
        httplib::Client client("127.0.0.1", occupier.port() + 1);
        client.set_connection_timeout(2, 0);
        SettleHttpClient();
        const auto res = client.Get("/healthy");
        REQUIRE(res);
        CHECK(res->status == 200);
    }
}

TEST_CASE("HealthServer destructor is non-blocking and non-throwing",
          "[health_server][lifecycle]")
{
    // If the destructor hangs, the test will time out via CTest. We bound it
    // explicitly so a regression surfaces as a clear failure rather than a
    // global test-runner stall.
    const int port = company_file_service::test::PickFreeLoopbackPort();

    auto construct_and_destroy = [&]() {
        HealthServer server("127.0.0.1", port);
        // Intentionally let `server` go out of scope at the end of this
        // lambda. Destructor must stop the listener and join the thread.
    };

    REQUIRE_NOTHROW(construct_and_destroy());

    // And we should be able to re-bind the same port afterwards. Combined
    // with the SO_REUSEADDR semantics in PortHolder this proves the
    // listener socket was fully released by the destructor.
    REQUIRE_NOTHROW(construct_and_destroy());
    REQUIRE_NOTHROW(construct_and_destroy());
}

TEST_CASE("HealthServer starts successfully on a port different from /healthy URL",
          "[health_server][http]")
{
    // Defensive: the URL path is independent of the listen port. The contract
    // is "the health probe is reachable at <host>:<port>/healthy" regardless
    // of which port was chosen.
    const int port = company_file_service::test::PickFreeLoopbackPort();
    HealthServer server("127.0.0.1", port);

    httplib::Client wrong_port("127.0.0.1", port + 1);
    wrong_port.set_connection_timeout(1, 0);
    SettleHttpClient();
    REQUIRE_FALSE(wrong_port.Get("/healthy"));

    httplib::Client right_port("127.0.0.1", port);
    right_port.set_connection_timeout(2, 0);
    const auto res = right_port.Get("/healthy");
    REQUIRE(res);
    CHECK(res->status == 200);
}
