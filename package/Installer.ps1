[CmdletBinding()]
param([ValidateSet('Install','Uninstall','Verify')][string]$Mode='Install',[string]$GamePath,[switch]$NonInteractive)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2
$packageRoot=$PSScriptRoot
$manifest=Get-Content -LiteralPath (Join-Path $packageRoot 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
function HashBytes([byte[]]$bytes) {
 $algorithm=[Security.Cryptography.SHA256]::Create()
 try { return ([BitConverter]::ToString($algorithm.ComputeHash($bytes))).Replace('-','').ToLowerInvariant() } finally {$algorithm.Dispose()}
}
function FileHash([string]$path) { if (!(Test-Path -LiteralPath $path -PathType Leaf)) {return $null};return (HashBytes ([IO.File]::ReadAllBytes($path))) }
function SafePath([string]$root,[string]$relative) {
 if ([IO.Path]::IsPathRooted($relative)) {throw 'Invalid absolute package path.'}
 $base=[IO.Path]::GetFullPath($root).TrimEnd('\')+'\'
 $full=[IO.Path]::GetFullPath((Join-Path $base $relative))
 if (!$full.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)) {throw 'Invalid path outside installation folder.'}
 return $full
}
function FindGame {
 $steamRoots=New-Object 'System.Collections.Generic.List[string]'
 foreach($key in @('HKCU:\Software\Valve\Steam','HKLM:\SOFTWARE\WOW6432Node\Valve\Steam','HKLM:\SOFTWARE\Valve\Steam')) {
  if(Test-Path $key){$props=Get-ItemProperty $key;foreach($field in @('SteamPath','InstallPath')) {if($props.PSObject.Properties[$field] -and $props.$field){$steamRoots.Add([string]$props.$field)}}}
 }
 if(${env:ProgramFiles(x86)}){$steamRoots.Add((Join-Path ${env:ProgramFiles(x86)} 'Steam'))}
 $libraries=New-Object 'System.Collections.Generic.List[string]'
 foreach($steam in @($steamRoots | Select-Object -Unique)) {
  $libraries.Add($steam)
  $vdf=Join-Path $steam 'steamapps\libraryfolders.vdf'
  if(Test-Path -LiteralPath $vdf){$txt=[IO.File]::ReadAllText($vdf);foreach($match in [regex]::Matches($txt,'"path"\s+"([^"]+)"')) {$libraries.Add($match.Groups[1].Value.Replace('\\','\'))}}
 }
 $found=New-Object 'System.Collections.Generic.List[string]'
 foreach($lib in @($libraries | Select-Object -Unique)) {
  $dir='Space Rangers HD A War Apart';$acf=Join-Path $lib 'steamapps\appmanifest_214730.acf'
  if(Test-Path -LiteralPath $acf){$m=[regex]::Match([IO.File]::ReadAllText($acf),'"installdir"\s+"([^"]+)"');if($m.Success){$dir=$m.Groups[1].Value}}
  $candidate=Join-Path $lib ('steamapps\common\'+$dir)
  if(Test-Path -LiteralPath (Join-Path $candidate 'Rangers.exe')){$found.Add([IO.Path]::GetFullPath($candidate.Replace('/','\')).TrimEnd('\'))}
 }
 $candidates=@($found | Sort-Object -Unique)
 if($candidates.Count -eq 1){return $candidates[0]}
 if($NonInteractive){throw 'Game directory was not uniquely detected. Supply -GamePath.'}
 if($candidates.Count -gt 1){for($i=0;$i -lt $candidates.Count;$i++){Write-Host (('{0}: {1}' -f ($i+1),$candidates[$i]))};$choice=Read-Host '请选择游戏编号，或输入完整游戏目录';$number=0;if([int]::TryParse($choice,[ref]$number) -and $number -ge 1 -and $number -le $candidates.Count){return $candidates[$number-1]};return $choice}
 return (Read-Host '未找到游戏，请粘贴包含 Rangers.exe 的游戏目录（可从 Steam 浏览本地文件获得）')
}
function ConfigBytes([byte[]]$bytes,[bool]$enable) {
 $skip=0;$enc=New-Object Text.UTF8Encoding($false)
 if($bytes.Length -ge 2 -and $bytes[0] -eq 255 -and $bytes[1] -eq 254){$enc=[Text.Encoding]::Unicode;$skip=2}
 elseif($bytes.Length -ge 2 -and $bytes[0] -eq 254 -and $bytes[1] -eq 255){$enc=[Text.Encoding]::BigEndianUnicode;$skip=2}
 elseif($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191){$enc=New-Object Text.UTF8Encoding($true);$skip=3}
 $txt=$enc.GetString($bytes,$skip,$bytes.Length-$skip)
 $m=[regex]::Match($txt,'(?m)^CurrentMod=([^\r\n]*)')
 $mods=@();if($m.Success){$mods=@($m.Groups[1].Value.Split(',') | ForEach-Object {$_.Trim()} | Where-Object {$_})}
 $mods=@($mods | Where-Object {$_ -ine 'Tweaks\Chinese' -and (!$enable -or ($_ -ine 'Tweaks\German' -and $_ -ine 'Tweaks\Spanish'))})
 if($enable){$mods+= 'Tweaks\Chinese'}
 $line='CurrentMod='+($mods -join ', ')
 if($m.Success){$txt=$txt.Remove($m.Index,$m.Length).Insert($m.Index,$line)}else{$txt+="`r`n$line`r`n"}
 [byte[]]$out=@($enc.GetPreamble())+@($enc.GetBytes($txt));return ,$out
}
function SaveBytes([string]$path,[byte[]]$bytes) {
 [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path)) | Out-Null
 [IO.File]::WriteAllBytes($path,$bytes)
}
function ReadBytes([string]$path) {return ,([IO.File]::ReadAllBytes($path))}
function StateWrite($state) {SaveBytes $statePath ([Text.Encoding]::UTF8.GetBytes(($state | ConvertTo-Json -Depth 12)))}
try {
 if(!$GamePath){$GamePath=FindGame}
 $GamePath=[IO.Path]::GetFullPath($GamePath.Trim().Trim('"'))
 if(!(Test-Path -LiteralPath (Join-Path $GamePath 'Rangers.exe') -PathType Leaf)){throw '目录不正确：没有找到 Rangers.exe。'}
 if(Get-Process -Name Rangers -ErrorAction SilentlyContinue){throw '请先退出游戏，再运行安装或卸载。'}
 $backupRoot=SafePath $GamePath '.srhd-zh-backup'
 $statePath=SafePath $backupRoot 'installation.json'
 $state=$null
 if(Test-Path -LiteralPath $statePath){$state=Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json;if($state.product -ne $manifest.product -or $state.version -ne $manifest.version){throw '发现其他版本的安装记录，请先用对应版本卸载。'}}
 $cfgPath=SafePath $GamePath 'Mods/ModCFG.txt'
 if($Mode -eq 'Uninstall') {
  if(!$state){throw '没有找到此安装器的备份记录，无法自动还原。'}
  $operations=New-Object 'System.Collections.Generic.List[object]'
  foreach($entry in $manifest.files) {
   $record=@($state.files | Where-Object {$_.path -eq $entry.path})
   if($record.Count -ne 1 -or $record[0].after -ne $entry.after){throw '安装记录不完整，已停止卸载。'}
   $record=$record[0];$target=SafePath $GamePath $entry.path
   if((FileHash $target) -ne $entry.after){throw ('文件已被更新或修改，已停止卸载以防覆盖：'+$entry.path+'。可通过 Steam 验证文件恢复游戏；备份仍然保留。')}
   $restore=$null
   if($record.existed){$original=SafePath $backupRoot $record.backup;if((FileHash $original) -ne $record.before){throw ('备份损坏：'+$entry.path)};$restore=ReadBytes $original}
   $operations.Add([pscustomobject]@{path=$target;data=$restore})
  }
  if(Test-Path -LiteralPath $cfgPath){$currentCfg=ReadBytes $cfgPath;if(!$state.configModified -and (HashBytes $currentCfg) -eq $state.configAfter){$originalCfg=SafePath $backupRoot $state.configBackup;if((FileHash $originalCfg) -ne $state.configBefore){throw '模组选项备份损坏。'};$restoreCfg=$null;if($state.configExisted){$restoreCfg=ReadBytes $originalCfg}}else{$restoreCfg=ConfigBytes $currentCfg $false};$operations.Add([pscustomobject]@{path=$cfgPath;data=$restoreCfg})}
 } else {
  foreach($entry in $manifest.validation){if((FileHash (SafePath $GamePath $entry.path)) -ne $entry.hash){throw ('不兼容的游戏资源：'+$entry.path+'。本包适用于 Steam 英文版 2.1.2500，请先恢复原版文件并选择英语。')}}
  $operations=New-Object 'System.Collections.Generic.List[object]'
  $records=New-Object 'System.Collections.Generic.List[object]'
  foreach($entry in $manifest.files) {
   $source=SafePath $packageRoot $entry.payload
   if((FileHash $source) -ne $entry.payloadHash){throw ('安装包文件损坏：'+$entry.payload+'。请重新下载并完整解压。')}
   $target=SafePath $GamePath $entry.path;$current=FileHash $target
   if($state){$record=@($state.files | Where-Object {$_.path -eq $entry.path});if($record.Count -ne 1 -or $current -ne $entry.after){throw ('已安装文件被修改，请先恢复或卸载：'+$entry.path)}}
   elseif($current -ne $entry.before){throw ('文件版本不匹配或已装其他补丁：'+$entry.path+'。请先恢复原版；本包不会覆盖未知版本。')}
   if($current -eq $entry.after){continue}
   if($entry.kind -eq 'patch') {
    $patch=Get-Content -LiteralPath $source -Raw -Encoding UTF8 | ConvertFrom-Json
    [byte[]]$data=New-Object byte[] ([int]$patch.length);$original=ReadBytes $target
    [Array]::Copy($original,$data,[Math]::Min($original.Length,$data.Length))
    foreach($change in $patch.changes){$block=[Convert]::FromBase64String($change.data);if($change.offset -lt 0 -or ($change.offset+$block.Length) -gt $data.Length){throw '二进制补丁范围错误。'};[Array]::Copy($block,0,$data,[int]$change.offset,$block.Length)}
   }else{$data=ReadBytes $source}
   if((HashBytes $data) -ne $entry.after){throw ('生成的文件校验失败：'+$entry.path)}
   $operations.Add([pscustomobject]@{path=$target;data=$data})
   $records.Add([pscustomobject]@{path=$entry.path;existed=($null -ne $current);before=$current;after=$entry.after;backup=$null})
  }
  if($Mode -eq 'Verify'){Write-Host '校验通过：游戏版本及安装包文件正常。' -ForegroundColor Green;exit 0}
  $configExisted=Test-Path -LiteralPath $cfgPath -PathType Leaf
  if($configExisted){$currentCfg=ReadBytes $cfgPath}else{[byte[]]$currentCfg=[Text.Encoding]::UTF8.GetBytes("CurrentMod=`r`n")}
  $newCfg=ConfigBytes $currentCfg $true
  $operations.Add([pscustomobject]@{path=$cfgPath;data=$newCfg})
  if(!$state){
   $backupID=[Guid]::NewGuid().ToString('N')
   foreach($record in $records){if($record.existed){$record.backup=$backupID+'/'+$record.path;$src=SafePath $GamePath $record.path;$dest=SafePath $backupRoot $record.backup;SaveBytes $dest (ReadBytes $src);if((FileHash $dest) -ne $record.before){throw '备份校验失败，尚未修改游戏。'}}}
   $cfgBackup=$backupID+'/ModCFG.txt';SaveBytes (SafePath $backupRoot $cfgBackup) $currentCfg
   $state=[pscustomobject]@{product=$manifest.product;version=$manifest.version;created=[DateTime]::UtcNow.ToString('o');files=@($records.ToArray());configBackup=$cfgBackup;configBefore=(HashBytes $currentCfg);configAfter=(HashBytes $newCfg);configExisted=$configExisted;configModified=$false}
  } else {if((HashBytes $currentCfg) -ne $state.configAfter){$state.configModified=$true};$state.configAfter=HashBytes $newCfg}
 }
 # Snapshot the entire transaction so any write failure can restore the exact pre-action state.
 $snapshots=New-Object 'System.Collections.Generic.List[object]'
 foreach($op in $operations){$previous=$null;if(Test-Path -LiteralPath $op.path){$previous=ReadBytes $op.path};$snapshots.Add([pscustomobject]@{path=$op.path;data=$previous})}
 $previousState=$null;if(Test-Path -LiteralPath $statePath){$previousState=ReadBytes $statePath}
 try {
  foreach($op in $operations){if($null -eq $op.data){Remove-Item -LiteralPath $op.path -Force}else{SaveBytes $op.path $op.data}}
  if($Mode -eq 'Install') {foreach($entry in $manifest.files){if((FileHash (SafePath $GamePath $entry.path)) -ne $entry.after){throw ('安装后校验失败：'+$entry.path)}};StateWrite $state}
  else {Remove-Item -LiteralPath $statePath -Force}
 } catch {
  $originalError=$_
  foreach($snapshot in $snapshots){try{if($null -eq $snapshot.data){if(Test-Path -LiteralPath $snapshot.path){Remove-Item -LiteralPath $snapshot.path -Force}}else{SaveBytes $snapshot.path $snapshot.data}}catch{Write-Warning ('无法还原 '+$snapshot.path+'，请保留 .srhd-zh-backup 中的备份。')}}
  try{if($null -ne $previousState){SaveBytes $statePath $previousState}elseif(Test-Path -LiteralPath $statePath){Remove-Item -LiteralPath $statePath -Force}}catch{Write-Warning '安装记录回滚失败，请保留备份。'}
  throw $originalError
 }
 if($Mode -eq 'Install'){Write-Host '安装完成，中文语言包已启用！请通过 Steam 启动游戏。' -ForegroundColor Green;Write-Host '在开始菜单的模组页面取消/勾选中文语言包，并确认后重新启动游戏，即可切换英语/中文。'}
 else{Write-Host '卸载完成，原文件已还原。备份仍保留，存档未改动。' -ForegroundColor Green}
 Write-Host ('游戏目录：'+$GamePath)
 exit 0
} catch {
 Write-Host ('操作未完成：'+$_.Exception.Message) -ForegroundColor Red
 if($_.Exception -is [UnauthorizedAccessException]){Write-Host '目录没有写入权限，请右键 Install.bat 或 Uninstall.bat，选择“以管理员身份运行”。'}
 exit 1
}
