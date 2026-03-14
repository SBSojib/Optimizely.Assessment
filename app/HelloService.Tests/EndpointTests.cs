using System.Net;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Mvc.Testing;

namespace HelloService.Tests;

public class EndpointTests(WebApplicationFactory<Program> factory)
    : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client = factory.CreateClient();

    // ── /health ──────────────────────────────────────────────────────────────

    [Fact]
    public async Task Health_Returns200()
    {
        var response = await _client.GetAsync("/health");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task Health_ReturnsStatusOkBody()
    {
        var body = await _client.GetFromJsonAsync<HealthBody>("/health");

        Assert.NotNull(body);
        Assert.Equal("ok", body.Status);
    }

    // ── /hello ───────────────────────────────────────────────────────────────

    [Fact]
    public async Task Hello_Returns200()
    {
        var response = await _client.GetAsync("/hello");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task Hello_ReturnsExpectedMessage()
    {
        var body = await _client.GetFromJsonAsync<HelloBody>("/hello");

        Assert.NotNull(body);
        Assert.Equal("Hello from hello-service!", body.Message);
    }

    [Fact]
    public async Task Hello_PodName_FallsBackToUnknown_WhenEnvVarAbsent()
    {
        var body = await _client.GetFromJsonAsync<HelloBody>("/hello");

        Assert.NotNull(body);
        Assert.Equal("unknown", body.PodName);
    }

    [Fact]
    public async Task Hello_TimestampUtc_IsValidIso8601()
    {
        var body = await _client.GetFromJsonAsync<HelloBody>("/hello");

        Assert.NotNull(body);
        Assert.True(
            DateTimeOffset.TryParse(body.TimestampUtc, out _),
            $"Expected a valid ISO 8601 timestamp, got: '{body.TimestampUtc}'"
        );
    }

    // ── /metrics ─────────────────────────────────────────────────────────────

    [Fact]
    public async Task Metrics_Returns200()
    {
        var response = await _client.GetAsync("/metrics");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    // ── unknown routes ───────────────────────────────────────────────────────

    [Fact]
    public async Task UnknownRoute_Returns404()
    {
        var response = await _client.GetAsync("/does-not-exist");

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    // ── response shape types ─────────────────────────────────────────────────

    private sealed record HealthBody(string Status);

    private sealed record HelloBody(
        string Message,
        string PodName,
        string TraceId,
        string TimestampUtc);
}
