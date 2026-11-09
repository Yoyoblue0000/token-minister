param(
    [Parameter(Mandatory = $true)][int]$Port,
    [Parameter(Mandatory = $true)][string]$FixturePath,
    [Parameter(Mandatory = $true)][string]$HeadersPath
)

$ErrorActionPreference = 'Stop'
$listener = [Net.HttpListener]::new()
$listener.Prefixes.Add("http://127.0.0.1:$Port/")
$listener.Start()
try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        if ($context.Request.Url.AbsolutePath -eq '/console/api/go/status') {
            $orgId = $context.Request.Headers['x-org-id']
            $cookieHeader = $context.Request.Headers['Cookie']
            [IO.File]::WriteAllText($HeadersPath, "x-org-id: $orgId`nCookie: $cookieHeader")
            if ($context.Request.QueryString['mode'] -eq '401') {
                $body = [Text.Encoding]::UTF8.GetBytes('{"_tag":"Unauthorized"}')
                $context.Response.StatusCode = 401
            }
            else {
                $body = [IO.File]::ReadAllBytes($FixturePath)
                $context.Response.StatusCode = 200
            }
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
