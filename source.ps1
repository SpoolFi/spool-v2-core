Get-Content .env | foreach {
    $name, $value = $_.split('=');

    if ([string]::IsNullOrWhiteSpace($name) -Or $name.Contains("#")) {
        continue;
    }

    Set-Content env:\$name $value;
}
