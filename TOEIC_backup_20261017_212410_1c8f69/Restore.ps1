$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$items = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'manifest.json') | ConvertFrom-Json
foreach ($item in $items) {
    $file = Join-Path $project $item.path
    if (Test-Path -LiteralPath $file) {
        if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $item.installedHash) {
            throw ('File đã được sửa sau khi cập nhật; chưa khôi phục: ' + $item.path)
        }
    }
}
foreach ($item in $items) {
    $file = Join-Path $project $item.path
    if ($item.existed) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot ('original/' + $item.path)) -Destination $file -Force }
    elseif (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file }
}
Write-Host 'Đã khôi phục mã nguồn và cấu hình. Không thay đổi database.'