$ErrorActionPreference = 'Stop'

# $drives = @("C");
$drives = @("C");
 
# The minimum disk size to check for raising the warning
$minSize = 100GB;

foreach ($d in $drives) {
    Write-Host ("Checking drive " + $d + " ...");
    $disk = Get-PSDrive $d;
    $total = $disk.Free + $disk.Used
    if ($total -lt $minSize) {
        Write-Error ("Drive " + $d + " has less than " + $minSize + " total size");
        exit 1
    }
}

