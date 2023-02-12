foreach ($line in Get-Content .env) {
    if ($line.StartsWith("#") -Or [String]::IsNullOrWhiteSpace($line)) {
        continue;
    }

    $name, $value = $line.split('=');

    if ([String]::IsNullOrWhiteSpace($value)) {
        continue;
    }

    Set-Item -Path env:$name -Value $value;
}
