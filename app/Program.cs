using System.Collections;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Google.Cloud.SecretManager.V1;
using Prometheus;

var builder = WebApplication.CreateBuilder(args);

builder.Logging.ClearProviders();
builder.Logging.AddJsonConsole(options =>
{
    options.UseUtcTimestamp = true;
});

var app = builder.Build();

// Load secrets from GCP Secret Manager via Workload Identity when SECRET_* refs exist.
// Env vars named SECRET_<X> are resolved to their secret value and re-exported as <X>.
var secretReferences = Environment
    .GetEnvironmentVariables()
    .Cast<DictionaryEntry>()
    .Select(entry => new
    {
        Key = entry.Key?.ToString(),
        SecretId = entry.Value?.ToString(),
    })
    .Where(entry => entry.Key is not null &&
                    entry.Key.StartsWith("SECRET_", StringComparison.Ordinal) &&
                    !string.IsNullOrWhiteSpace(entry.SecretId))
    .ToList();

if (secretReferences.Count > 0)
{
    var gcpProjectId = Environment.GetEnvironmentVariable("GCP_PROJECT_ID")
                       ?? throw new InvalidOperationException("GCP_PROJECT_ID must be configured when SECRET_* references are set.");

    try
    {
        var client = SecretManagerServiceClient.Create();
        foreach (var secretReference in secretReferences)
        {
            var envName = secretReference.Key!["SECRET_".Length..];
            var name = new SecretVersionName(gcpProjectId, secretReference.SecretId!, "latest");
            var response = client.AccessSecretVersion(name);
            Environment.SetEnvironmentVariable(envName, response.Payload.Data.ToStringUtf8());
            app.Logger.LogInformation("Loaded secret {SecretId} as {EnvVar}", secretReference.SecretId, envName);
        }
    }
    catch (Exception ex)
    {
        app.Logger.LogError(ex, "Failed to load secrets from Secret Manager.");
        throw;
    }
}

// API key must be present, whether provided directly or loaded from Secret Manager.
var apiKey = Environment.GetEnvironmentVariable("API_KEY")
             ?? throw new InvalidOperationException("API_KEY must be configured for hello-service.");

var requestCounter = Metrics.CreateCounter(
    "hello_service_http_requests_total",
    "Total HTTP requests received by hello-service.",
    new CounterConfiguration { LabelNames = new[] { "method", "endpoint", "status_code" } }
);

app.Use(async (context, next) =>
{
    await next();
    var path = context.Request.Path.Value ?? "unknown";
    if (path is not "/metrics" and not "/health")
    {
        requestCounter.WithLabels(
            context.Request.Method,
            path,
            context.Response.StatusCode.ToString()
        ).Inc();
    }
});

app.MapGet("/health", () => Results.Ok(new { status = "ok" }));

// /hello is always protected by the configured API key.
// Clients must send Authorization: Bearer <key> or X-API-Key: <key>.
app.MapGet("/hello", (HttpContext context) =>
{
    var authHeader = context.Request.Headers.Authorization.FirstOrDefault();
    var suppliedKey = authHeader?.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase) == true
        ? authHeader["Bearer ".Length..].Trim()
        : context.Request.Headers["X-API-Key"].FirstOrDefault();

    if (!ApiKeyMatches(suppliedKey, apiKey))
    {
        return Results.Json(
            new { error = "Missing or invalid API key. Use Authorization: Bearer <key> or X-API-Key header." },
            statusCode: 401
        );
    }

    var podName = Environment.GetEnvironmentVariable("POD_NAME") ?? "unknown";
    var traceId = context.TraceIdentifier;

    Console.WriteLine(JsonSerializer.Serialize(new
    {
        severity = "INFO",
        message = "hello_request_handled",
        trace_id = traceId,
        status_code = 200,
        method = context.Request.Method,
        path = context.Request.Path.Value,
        pod_name = podName,
        timestamp_utc = DateTime.UtcNow.ToString("o")
    }));

    return Results.Ok(new
    {
        message = "Hello from hello-service!",
        podName,
        traceId,
        timestampUtc = DateTime.UtcNow.ToString("o")
    });
});

app.MapMetrics();

app.Run();

static bool ApiKeyMatches(string? suppliedKey, string expectedApiKey)
{
    if (string.IsNullOrEmpty(suppliedKey))
    {
        return false;
    }

    var suppliedBytes = Encoding.UTF8.GetBytes(suppliedKey);
    var expectedBytes = Encoding.UTF8.GetBytes(expectedApiKey);

    return CryptographicOperations.FixedTimeEquals(suppliedBytes, expectedBytes);
}

// Required for WebApplicationFactory<Program> in integration tests.
public partial class Program { }
