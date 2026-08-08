param(
    [Parameter(Mandatory = $true)][int]$Port,
    [Parameter(Mandatory = $true)][string]$FixturePath
)

$ErrorActionPreference = 'Stop'
$listener = [Net.HttpListener]::new()
$listener.Prefixes.Add("http://127.0.0.1:$Port/")
$listener.Start()
try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        if ($context.Request.Url.AbsolutePath -eq '/api/menubar/summary') {
            $body = [IO.File]::ReadAllBytes($FixturePath)
            $context.Response.StatusCode = 200
            $context.Response.ContentType = 'application/json'
            $context.Response.ContentLength64 = $body.Length
            $context.Response.OutputStream.Write($body, 0, $body.Length)
        }
        else {
            $context.Response.StatusCode = 404
        }
        $context.Response.Close()
    }
}
finally {
    $listener.Stop()
    $listener.Close()
}
