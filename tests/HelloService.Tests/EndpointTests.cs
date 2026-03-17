using System.Net;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Mvc.Testing;
using Xunit;

namespace HelloService.Tests;

public class EndpointTests : IClassFixture<WebApplicationFactory<Program>>, IDisposable
{
    private const string TestApiKey = "test-api-key";

    private readonly HttpClient _client;
    private readonly string? _originalApiKey = Environment.GetEnvironmentVariable("API_KEY");
    private readonly string? _originalProjectId = Environment.GetEnvironmentVariable("GCP_PROJECT_ID");
    private readonly string? _originalSecretApiKey = Environment.GetEnvironmentVariable("SECRET_API_KEY");

    public EndpointTests(WebApplicationFactory<Program> factory)
    {
        Environment.SetEnvironmentVariable("API_KEY", TestApiKey);
        Environment.SetEnvironmentVariable("GCP_PROJECT_ID", null);
        Environment.SetEnvironmentVariable("SECRET_API_KEY", null);

        _client = factory.CreateClient();
    }

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
    public async Task Hello_WithoutApiKey_Returns401()
    {
        var response = await _client.GetAsync("/hello");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Hello_WithBearerToken_Returns200()
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, "/hello");
        request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", TestApiKey);

        var response = await _client.SendAsync(request);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task Hello_ReturnsExpectedMessage()
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, "/hello");
        request.Headers.Add("X-API-Key", TestApiKey);

        var response = await _client.SendAsync(request);
        var body = await response.Content.ReadFromJsonAsync<HelloBody>();

        Assert.NotNull(body);
        Assert.Equal("Hello from hello-service!", body.Message);
    }

    [Fact]
    public async Task Hello_PodName_FallsBackToUnknown_WhenEnvVarAbsent()
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, "/hello");
        request.Headers.Add("X-API-Key", TestApiKey);

        var response = await _client.SendAsync(request);
        var body = await response.Content.ReadFromJsonAsync<HelloBody>();

        Assert.NotNull(body);
        Assert.Equal("unknown", body.PodName);
    }

    [Fact]
    public async Task Hello_TimestampUtc_IsValidIso8601()
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, "/hello");
        request.Headers.Add("X-API-Key", TestApiKey);

        var response = await _client.SendAsync(request);
        var body = await response.Content.ReadFromJsonAsync<HelloBody>();

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

    public void Dispose()
    {
        Environment.SetEnvironmentVariable("API_KEY", _originalApiKey);
        Environment.SetEnvironmentVariable("GCP_PROJECT_ID", _originalProjectId);
        Environment.SetEnvironmentVariable("SECRET_API_KEY", _originalSecretApiKey);
    }
}
