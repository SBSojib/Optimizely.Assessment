using System.Text.Json;
using Prometheus;

var builder = WebApplication.CreateBuilder(args);

builder.Logging.ClearProviders();
builder.Logging.AddJsonConsole(options =>
{
    options.UseUtcTimestamp = true;
});

var app = builder.Build();

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

app.MapGet("/hello", (HttpContext context) =>
{
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
