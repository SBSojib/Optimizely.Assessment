using System.Collections;
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

// Load secrets from GCP Secret Manager via Workload Identity.
// Env vars named SECRET_<X> are resolved to their secret value and re-exported as <X>.
// If Secret Manager is unavailable (e.g. local dev), the app starts without secrets.
var gcpProjectId = Environment.GetEnvironmentVariable("GCP_PROJECT_ID");
if (!string.IsNullOrEmpty(gcpProjectId))
{
    try
    {
        var client = SecretManagerServiceClient.Create();
        foreach (DictionaryEntry entry in Environment.GetEnvironmentVariables())
        {
            var key = entry.Key?.ToString();
            var secretId = entry.Value?.ToString();
            if (key is null || !key.StartsWith("SECRET_") || string.IsNullOrEmpty(secretId))
                continue;

            var envName = key["SECRET_".Length..];
            var name = new SecretVersionName(gcpProjectId, secretId, "latest");
            var response = client.AccessSecretVersion(name);
            Environment.SetEnvironmentVariable(envName, response.Payload.Data.ToStringUtf8());
            app.Logger.LogInformation("Loaded secret {SecretId} as {EnvVar}", secretId, envName);
        }
    }
    catch (Exception ex)
    {
        app.Logger.LogWarning(ex, "Could not load secrets from Secret Manager — continuing without them");
    }
}

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

// API key (from Secret Manager) optionally protects /hello. If set, request must send
// Authorization: Bearer <key> or X-API-Key: <key>. If not set, /hello is open (e.g. local dev).
var apiKey = Environment.GetEnvironmentVariable("API_KEY");

app.MapGet("/hello", (HttpContext context) =>
{
    if (!string.IsNullOrEmpty(apiKey))
    {
        var authHeader = context.Request.Headers.Authorization.FirstOrDefault();
        var suppliedKey = authHeader?.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase) == true
            ? authHeader["Bearer ".Length..].Trim()
            : context.Request.Headers["X-API-Key"].FirstOrDefault();

        if (suppliedKey != apiKey)
        {
            return Results.Json(
                new { error = "Missing or invalid API key. Use Authorization: Bearer <key> or X-API-Key header." },
                statusCode: 401
            );
        }
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

// Required for WebApplicationFactory<Program> in integration tests.
public partial class Program { }
