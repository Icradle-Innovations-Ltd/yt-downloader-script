# YouTube Downloader (MP4/MP3/Subtitles with Folder Sorting) - v7 with Enhanced GPU Acceleration

# Path setup
$ffmpegPath = Join-Path $PSScriptRoot "ffmpeg\bin\ffmpeg.exe"
$basePath = Join-Path $PSScriptRoot "Downloads"
$audioPath = Join-Path $basePath "AudioOnly"
$videoPath = Join-Path $basePath "VideoOnly"
$fullPath  = Join-Path $basePath "VideoWithAudio"
$subsPath  = Join-Path $basePath "SubtitlesOnly"
$logsPath  = Join-Path $PSScriptRoot "Logs"

# Create all necessary directories
$paths = @($basePath, $audioPath, $videoPath, $fullPath, $subsPath, $logsPath)
foreach ($p in $paths) { if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p | Out-Null } }

# Logging setup
$logFile = Join-Path $logsPath "download_log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
function Write-Log {
    param(
        [string]$Message,
        [string]$ForegroundColor = "White"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $logFile -Append
    Write-Host -ForegroundColor $ForegroundColor $Message
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Clear-Host
Write-Log "===============================================" Green
Write-Log "    YouTube Downloader (MP4, MP3, Subtitles)" Green
Write-Log "    With GPU Acceleration & Fragmentation" Green
Write-Log "===============================================" Green

# Dependency check
if (-Not (Test-Path $ffmpegPath)) {
    Write-Log "ERROR: ffmpeg.exe not found at $ffmpegPath" Red
    Exit 1
}
if (-Not (Get-Command "yt-dlp.exe" -ErrorAction SilentlyContinue)) {
    Write-Log "ERROR: yt-dlp.exe not found in PATH" Red
    Exit 1
}

# Function to detect the best available hardware acceleration method
function Get-BestHWAccel {
    Write-Log "Detecting available hardware acceleration methods..." Cyan
    try {
        $hwaccels = & $ffmpegPath -hwaccels 2>&1
        $hwaccelList = $hwaccels | Where-Object { $_ -match '^\s*(cuda|amf|qsv|d3d11va|dxva2|nvenc|vaapi)' } | ForEach-Object { $_.Trim() }
        
        # Check for NVIDIA GPU specifically
        $hasNvidia = $false
        try {
            $gpuInfo = Get-WmiObject -Class Win32_VideoController | Where-Object { $_.Name -match "NVIDIA" }
            if ($gpuInfo) {
                $hasNvidia = $true
                Write-Log "Detected NVIDIA GPU: $($gpuInfo.Name)" Green
            }
        } catch {
            Write-Log "Could not detect GPU information via WMI" Yellow
        }
        
        # If NVIDIA GPU is detected, prioritize NVIDIA-specific acceleration
        if ($hasNvidia) {
            if ($hwaccelList -contains "cuda") {
                Write-Log "Selected hardware acceleration: CUDA (NVIDIA)" Green
                return "nvidia"  # Special case for our script to use NVIDIA-specific settings
            } elseif ($hwaccelList -contains "nvenc") {
                Write-Log "Selected hardware acceleration: NVENC (NVIDIA)" Green
                return "nvidia"  # Special case for our script to use NVIDIA-specific settings
            }
        }
        
        # Priority order based on general performance
        $accelPriority = @("cuda", "nvenc", "amf", "qsv", "d3d11va", "dxva2", "vaapi")
        
        foreach ($accel in $accelPriority) {
            if ($hwaccelList -contains $accel) {
                Write-Log "Selected hardware acceleration: $accel" Green
                return $accel
            }
        }
        
        Write-Log "No preferred hardware acceleration found, using software encoding" Yellow
        return $null
    }
    catch {
        Write-Log "Error detecting hardware acceleration: $($_.Exception.Message)" Yellow
        return $null
    }
}

# Function to fix the post-processor arguments warning
function Get-YtDlpCommand {
    param (
        [string]$Format,
        [string]$Output,
        [string]$Url,
        [string]$FfmpegArgs,
        [string]$PostProcessArgs,
        [string]$PlaylistFlag,
        [int]$ConcurrentFragments,
        [string]$BufferSize,
        [string]$SubtitleLanguage,
        [switch]$AudioOnly,
        [string]$AudioQuality,
        [switch]$VideoOnly,
        [switch]$SkipSubtitles,
        [switch]$NetworkReliable
    )
    
    $command = "yt-dlp.exe -f $Format"
    
    if ($AudioOnly) {
        # Fix for M4A to MP3 conversion issues:
        # 1. Force output extension to be .mp3
        # 2. Add --fixup warn to handle container issues
        # 3. Add --audio-format mp3 to ensure MP3 output
        # 4. Add --no-warnings to suppress DASH m4a warnings
        $command += " -x --audio-format mp3 --audio-quality $AudioQuality --fixup warn --no-warnings"
        
        # Ensure the output path ends with .mp3 to avoid container issues
        if ($Output -notmatch '\.mp3\"\)$') {
            $Output = $Output -replace '\.%(ext)s', '.mp3'
        }
    } else {
        $command += " --merge-output-format mp4"
    }
    
    if (-not $SkipSubtitles) {
        $command += " --write-sub --write-auto-sub --sub-lang $SubtitleLanguage --convert-subs=srt"
    }
    
    # Add network reliability parameters
    if ($NetworkReliable) {
        # Standard network settings
        $command += " $PlaylistFlag --ffmpeg-location $ffmpegPath --concurrent-fragments $ConcurrentFragments"
        $command += " --retries 20 --fragment-retries 20 --continue"
    } else {
        # More conservative network settings for unreliable connections
        # 1. Reduce concurrent fragments to avoid overwhelming the connection
        $reducedFragments = [Math]::Max(1, [Math]::Floor($ConcurrentFragments / 2))
        # 2. Increase retry count and add retry sleep
        # 3. Add socket timeout and increase fragment retries
        # 4. Add file access retries for intermittent file system issues
        $command += " $PlaylistFlag --ffmpeg-location $ffmpegPath --concurrent-fragments $reducedFragments"
        $command += " --retries 30 --fragment-retries 30 --retry-sleep 5 --file-access-retries 10 --continue"
        $command += " --socket-timeout 30 --extractor-retries 5"
    }
    
    if (-not $AudioOnly) {
        $command += " --prefer-free-formats"
    }
    
    $command += " --buffer-size $BufferSize"
    $command += " --downloader-args `"ffmpeg:$FfmpegArgs`""
    
    # Use the correct parameter for post-processing arguments
    if ($PostProcessArgs) {
        $command += " --postprocessor-args `"ffmpeg:$PostProcessArgs`""
    }
    
    # Add remaining parameters
    $command += " --no-check-certificate --no-part --no-mtime --progress --newline -o `"$Output`" `"$Url`""
    
    return $command
}

# Function to get ffmpeg arguments based on hardware acceleration method
function Get-FFmpegArgs {
    param (
        [string]$HWAccel,
        [string]$MediaType = "video",  # "video" or "audio"
        [switch]$MobileOptimized = $true  # Default to mobile-optimized settings
    )
    
    $ffmpegArgs = "-nostats -loglevel 0"
    
    if ($HWAccel) {
        switch ($HWAccel) {
            "nvidia" {
                if ($MediaType -eq "video") {
                    if ($MobileOptimized) {
                        # Mobile-optimized settings for NVIDIA GPUs for video with better compatibility
                        # Use p2 preset for faster encoding (p1=fastest, p7=highest quality)
                        # Lower bitrate and buffer size for better playback on mobile devices
                        # Add -pix_fmt yuv420p for better compatibility
                        $ffmpegArgs = "-hwaccel cuda -hwaccel_output_format cuda -c:v h264_nvenc -preset p2 -tune hq -rc:v vbr_hq -cq:v 23 -b:v 2M -maxrate:v 4M -bufsize:v 8M -pix_fmt yuv420p -threads 8 -nostats -loglevel 0"
                        Write-Log "Using mobile-optimized NVIDIA GPU acceleration for smooth playback on all devices" Cyan
                    } else {
                        # High-quality settings for NVIDIA GPUs for video
                        $ffmpegArgs = "-hwaccel cuda -hwaccel_output_format cuda -c:v h264_nvenc -preset p4 -tune hq -rc:v vbr_hq -cq:v 18 -b:v 0 -maxrate:v 15M -bufsize:v 30M -threads 8 -nostats -loglevel 0"
                        Write-Log "Using balanced NVIDIA GPU acceleration for high quality and good performance" Cyan
                    }
                } else {
                    # Specific optimized settings for NVIDIA GPUs for audio
                    # Use ultrafast preset and optimized audio encoding settings
                    $ffmpegArgs = "-hwaccel cuda -hwaccel_output_format cuda -c:v h264_nvenc -preset p1 -tune hq -c:a libmp3lame -qscale:a 2 -ar 44100 -ac 2 -threads 8 -nostats -loglevel 0"
                    Write-Log "Using high-performance NVIDIA GPU acceleration for audio processing" Cyan
                }
            }
            "cuda" {
                if ($MediaType -eq "video" -and $MobileOptimized) {
                    $ffmpegArgs = "-hwaccel cuda -hwaccel_output_format cuda -c:v h264_nvenc -preset p2 -tune hq -rc:v vbr_hq -cq:v 23 -b:v 2M -maxrate:v 4M -bufsize:v 8M -pix_fmt yuv420p -threads 8 -nostats -loglevel 0"
                    Write-Log "Using mobile-optimized CUDA acceleration for smooth playback on all devices" Cyan
                } else {
                    $ffmpegArgs = "-hwaccel cuda -hwaccel_output_format cuda -c:v h264_nvenc -preset p4 -tune hq -nostats -loglevel 0"
                    Write-Log "Using NVIDIA CUDA acceleration for $MediaType processing" Cyan
                }
            }
            "nvenc" {
                if ($MediaType -eq "video" -and $MobileOptimized) {
                    $ffmpegArgs = "-c:v h264_nvenc -preset p2 -tune hq -rc:v vbr_hq -cq:v 23 -b:v 2M -maxrate:v 4M -bufsize:v 8M -pix_fmt yuv420p -threads 8 -nostats -loglevel 0"
                    Write-Log "Using mobile-optimized NVENC acceleration for smooth playback on all devices" Cyan
                } else {
                    $ffmpegArgs = "-c:v h264_nvenc -preset p4 -tune hq -nostats -loglevel 0"
                    Write-Log "Using NVIDIA NVENC acceleration for $MediaType processing" Cyan
                }
            }
            "amf" {
                if ($MediaType -eq "video") {
                    if ($MobileOptimized) {
                        $ffmpegArgs = "-hwaccel amf -c:v h264_amf -quality balanced -rc vbr_peak -qp_i 26 -qp_p 28 -b:v 2M -maxrate 4M -bufsize 8M -pix_fmt yuv420p -threads 8 -nostats -loglevel 0"
                        Write-Log "Using mobile-optimized AMD AMF acceleration for smooth playback on all devices" Cyan
                    } else {
                        $ffmpegArgs = "-hwaccel amf -c:v h264_amf -quality speed -nostats -loglevel 0"
                        Write-Log "Using AMD AMF acceleration for video processing" Cyan
                    }
                } else {
                    # Optimized settings for AMD GPUs for audio
                    $ffmpegArgs = "-hwaccel amf -c:v h264_amf -quality speed -c:a libmp3lame -qscale:a 2 -ar 44100 -ac 2 -threads 8 -nostats -loglevel 0"
                    Write-Log "Using high-performance AMD AMF acceleration for audio processing" Cyan
                }
            }
            "qsv" {
                if ($MediaType -eq "video") {
                    if ($MobileOptimized) {
                        $ffmpegArgs = "-hwaccel qsv -hwaccel_output_format qsv -c:v h264_qsv -preset medium -b:v 2M -maxrate 4M -bufsize 8M -pix_fmt yuv420p -threads 8 -nostats -loglevel 0"
                        Write-Log "Using mobile-optimized Intel QuickSync acceleration for smooth playback on all devices" Cyan
                    } else {
                        $ffmpegArgs = "-hwaccel qsv -hwaccel_output_format qsv -c:v h264_qsv -preset fast -nostats -loglevel 0"
                        Write-Log "Using Intel QuickSync acceleration for video processing" Cyan
                    }
                } else {
                    # Optimized settings for Intel GPUs for audio
                    $ffmpegArgs = "-hwaccel qsv -hwaccel_output_format qsv -c:v h264_qsv -preset veryfast -c:a libmp3lame -qscale:a 2 -ar 44100 -ac 2 -threads 8 -nostats -loglevel 0"
                    Write-Log "Using high-performance Intel QuickSync acceleration for audio processing" Cyan
                }
            }
            "d3d11va" {
                if ($MediaType -eq "video" -and $MobileOptimized) {
                    # For DirectX 11, we need to use a software encoder after hardware decoding for better control
                    $ffmpegArgs = "-hwaccel d3d11va -c:v libx264 -preset medium -crf 23 -maxrate 4M -bufsize 8M -pix_fmt yuv420p -threads 8 -nostats -loglevel 0"
                    Write-Log "Using mobile-optimized DirectX 11 acceleration for smooth playback on all devices" Cyan
                } else {
                    $ffmpegArgs = "-hwaccel d3d11va -nostats -loglevel 0"
                    Write-Log "Using DirectX 11 acceleration for $MediaType processing" Cyan
                }
            }
            "dxva2" {
                if ($MediaType -eq "video" -and $MobileOptimized) {
                    # For DXVA2, we need to use a software encoder after hardware decoding for better control
                    $ffmpegArgs = "-hwaccel dxva2 -c:v libx264 -preset medium -crf 23 -maxrate 4M -bufsize 8M -pix_fmt yuv420p -threads 8 -nostats -loglevel 0"
                    Write-Log "Using mobile-optimized DirectX Video Acceleration for smooth playback on all devices" Cyan
                } else {
                    $ffmpegArgs = "-hwaccel dxva2 -nostats -loglevel 0"
                    Write-Log "Using DirectX Video Acceleration for $MediaType processing" Cyan
                }
            }
            default {
                if ($MediaType -eq "video" -and $MobileOptimized) {
                    # Software encoding optimized for mobile
                    $ffmpegArgs = "-c:v libx264 -preset medium -crf 23 -maxrate 4M -bufsize 8M -pix_fmt yuv420p -threads 8 -nostats -loglevel 0"
                    Write-Log "Using mobile-optimized software encoding for smooth playback on all devices" Yellow
                } else {
                    $ffmpegArgs = "-nostats -loglevel 0"
                    Write-Log "Using standard processing for $MediaType" Yellow
                }
            }
        }
    }
    
    return $ffmpegArgs
}

# Check yt-dlp version
try {
    $version = yt-dlp.exe --version
    Write-Log "yt-dlp version: $version" Cyan
}
catch {
    Write-Log "WARNING: Could not determine yt-dlp version." Yellow
}

# Check if yt-dlp needs updating
$updateYtDlp = Read-Host "Check for yt-dlp updates? (y/N)"
if ($updateYtDlp -eq 'y' -or $updateYtDlp -eq 'Y') {
    Write-Log "Checking for yt-dlp updates... (this may take a moment)" Cyan
    Write-Log "If this takes too long, you can press Ctrl+C to cancel" Yellow
    try {
        $updateOutput = yt-dlp.exe -U
        Write-Log "yt-dlp update check completed successfully" Green
        
        # Check version again after update
        try {
            $newVersion = yt-dlp.exe --version
            Write-Log "yt-dlp version after update: $newVersion" Cyan
        }
        catch {
            Write-Log "WARNING: Could not determine yt-dlp version after update." Yellow
        }
    }
    catch {
        Write-Log "WARNING: Update check failed. Continuing with current version." Yellow
    }
}

Write-Log "Dependencies verified: ffmpeg.exe and yt-dlp.exe found" Green

# Load config
$configPath = Join-Path $PSScriptRoot "ytdl_config.json"
$defaultConfig = @{
    DefaultResolution = "1080"
    DefaultAudioQuality = "192"
    MaxConcurrentFragments = 32  # Increased from 16 to 32 for faster downloads
    MaxAudioFragments = 64       # Higher value specifically for audio downloads
    SubtitleLanguage = "en"
    BufferSize = "16M"           # Buffer size for video downloads
    AudioBufferSize = "32M"      # Larger buffer size for audio downloads
    EnableHWAccel = $true        # Enable hardware acceleration
    PreferredHWAccel = "auto"    # Auto-detect the best hardware acceleration method
    AudioThreads = 8             # Number of threads to use for audio processing
}
if (-not (Test-Path $configPath)) {
    $defaultConfig | ConvertTo-Json | Out-File $configPath -Encoding UTF8
}
$config = Get-Content $configPath | ConvertFrom-Json

# URL input
function Test-ValidUrl($url) {
    return $url -match "^(https?://)?(www\.)?(youtube\.com|youtu\.be)/.+$"
}
do {
    $url = Read-Host "`nEnter YouTube URL (video or playlist)"
    if (-not (Test-ValidUrl $url)) {
        Write-Log "Invalid YouTube URL. Please try again." Yellow
    }
} until (Test-ValidUrl $url)
Write-Log "URL validated: $url" Green

# Playlist support
$playlist = Read-Host "`nDownload entire playlist? (y/N)"
$playlistFlag = if ($playlist -eq 'y' -or $playlist -eq 'Y') { "--yes-playlist" } else { "--no-playlist" }

# Menu
function Show-Menu {
    Write-Log "`nSelect download option:" Cyan
    Write-Host "1. Video with Audio (MP4)"
    Write-Host "2. Video Only (MP4)"
    Write-Host "3. Audio Only (MP3)"
    Write-Host "4. Subtitles Only (.srt)"
    
    do {
        $choice = Read-Host "Enter choice (1-4)"
        if ($choice -notmatch "^[1-4]$") {
            Write-Log "Invalid choice. Please enter a number between 1 and 4." Yellow
        }
    } until ($choice -match "^[1-4]$")
    
    return $choice
}

function Get-Resolution {
    Write-Log "`nSelect resolution:" Cyan
    $resOptions = @("1. 2160p (4K)", "2. 1440p", "3. 1080p", "4. 720p", "5. 480p", "6. 360p", "7. 240p", "8. 144p")
    $resOptions | ForEach-Object { Write-Host $_ }
    
    do {
        $res = Read-Host "Enter choice (1-8)"
        $resMap = @{"1"="2160";"2"="1440";"3"="1080";"4"="720";"5"="480";"6"="360";"7"="240";"8"="144"}
        if (-not $resMap.ContainsKey($res)) {
            Write-Log "Invalid choice. Please enter a number between 1 and 8." Yellow
        }
    } until ($resMap.ContainsKey($res))
    
    return $resMap[$res]
}

function Get-AudioQuality {
    Write-Log "`nSelect MP3 audio quality:" Cyan
    Write-Host "1. MP3 - 320kbps"
    Write-Host "2. MP3 - 256kbps"
    Write-Host "3. MP3 - 192kbps"
    Write-Host "4. MP3 - 128kbps"
    
    do {
        $q = Read-Host "Enter choice (1-4)"
        $qMap = @{"1"=@("0","320");"2"=@("1","256");"3"=@("2","192");"4"=@("3","128")}
        if (-not $qMap.ContainsKey($q)) {
            Write-Log "Invalid choice. Please enter a number between 1 and 4." Yellow
        }
    } until ($qMap.ContainsKey($q))
    
    return $qMap[$q]
}

# Function to check if subtitles are available
function Test-SubtitlesAvailable {
    param (
        [string]$Url,
        [string]$Language
    )
    
    Write-Log "Checking if subtitles are available..." Cyan
    
    try {
        # Use a timeout to prevent hanging
        $job = Start-Job -ScriptBlock {
            param($ytdlpPath, $url)
            & $ytdlpPath --list-subs --skip-download $url 2>&1
        } -ArgumentList "yt-dlp.exe", $Url
        
        # Wait for the job to complete with a timeout
        $completed = Wait-Job -Job $job -Timeout 15
        
        if ($completed -eq $null) {
            # Job timed out
            Stop-Job -Job $job
            Remove-Job -Job $job -Force
            Write-Log "Subtitle check timed out. Proceeding with download attempt anyway..." Yellow
            return $true # Assume subtitles might be available and try downloading
        }
        
        $output = Receive-Job -Job $job
        Remove-Job -Job $job
        
        # Check for both manual subtitles and automatic captions
        $hasManualSubs = $output -match "Available subtitles for"
        $hasAutoCaptions = $output -match "Available automatic captions for"
        
        # If the output explicitly says there are no subtitles AND no auto captions are found
        if (($output -match "has no subtitles" -or $output -match "does not have subtitles") -and -not $hasAutoCaptions) {
            Write-Log "This video does not have any subtitles or automatic captions available." Yellow
            return $false
        }
        
        # Check for specific language in manual subtitles
        if ($hasManualSubs -and ($output -match "Language\s+$Language\s+" -or $output -match "$Language\s+[A-Za-z]+\s+vtt")) {
            Write-Log "Manual subtitles found for language: $Language" Green
            return $true
        }
        
        # Check for specific language in automatic captions
        if ($hasAutoCaptions -and ($output -match "$Language\s+[A-Za-z]+\s+vtt" -or $output -match "en-orig\s+English \(Original\)\s+vtt")) {
            Write-Log "Automatic captions found for language: $Language" Green
            return $true
        }
        
        # If we have auto captions but couldn't find the specific language, we'll try anyway
        if ($hasAutoCaptions) {
            Write-Log "Automatic captions are available. Attempting to download for language: $Language" Yellow
            return $true
        }
        
        Write-Log "No subtitles or captions found for language: $Language" Yellow
        return $false
    }
    catch {
        Write-Log "Error checking subtitles: $($_.Exception.Message)" Yellow
        Write-Log "Proceeding with download attempt anyway..." Yellow
        return $true # Try downloading anyway
    }
}

# Function to convert bytes to MB
function ConvertTo-MB {
    param ([double]$Bytes)
    if ($Bytes -eq $null -or $Bytes -le 0) { return "N/A" }
    $mb = [math]::Round($Bytes / 1MB, 2)
    return "$mb MB"
}

# Function to estimate file size in bytes
function Estimate-FileSize {
    param (
        [double]$BitrateKbps,  # Bitrate in kbps
        [double]$DurationSeconds
    )
    if ($BitrateKbps -eq $null -or $DurationSeconds -eq $null) { return $null }
    # Convert kbps to bits, multiply by duration, divide by 8 for bytes
    $bytes = ($BitrateKbps * 1000 * $DurationSeconds) / 8
    return $bytes
}

# Function to check available video formats and resolutions with size estimates
function Get-AvailableFormats {
    param (
        [string]$Url,
        [int]$TimeoutSeconds = 30
    )
    
    Write-Log "Checking available video formats and sizes..." Cyan
    
    try {
        # Create a process object with timeout
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "yt-dlp.exe"
        $psi.Arguments = "$Url --skip-download --no-playlist --dump-json"
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        
        # Start the process
        $process.Start() | Out-Null
        
        # Create a task to read the output
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        
        # Wait for the process to exit or timeout
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            Write-Log "Timeout while checking video formats. Using standard resolutions." Yellow
            try {
                $process.Kill()
            } catch {
                # Process may have exited between our check and the kill command
            }
            return @{
                Resolutions = @(2160, 1440, 1080, 720, 480, 360, 240, 144)
                AudioBitrates = @(320, 256, 192, 128)
                VideoSizes = @{}
                AudioSizes = @{}
                Duration = 0
            }
        }
        
        # Get the output and parse JSON
        try {
            $json = $outputTask.Result | ConvertFrom-Json
            $formats = $json.formats
            $duration = $json.duration  # Video duration in seconds
            
            # Define target values
            $targetResolutions = @("2160", "1440", "1080", "720", "480", "360", "240", "144")
            $targetBitrates = @("320", "256", "192", "128")
            
            # Get all video formats (not just MP4)
            $videoFormats = $formats | Where-Object {
                $_.vcodec -ne "none"
            }
            
            # Check if there are formats with both video and audio
            $combinedFormats = $videoFormats | Where-Object {
                $_.acodec -ne "none"
            }
            
            # If we have combined formats, prefer those
            $formatsToUse = if ($combinedFormats -and $combinedFormats.Count -gt 0) {
                Write-Log "Found formats with both video and audio" Green
                $combinedFormats
            } else {
                Write-Log "No combined formats found, will need to merge video and audio" Yellow
                $videoFormats
            }
            
            # Store format IDs for each resolution to ensure we download exactly what we analyzed
            $formatIds = @{}
            
            # Audio-only formats
            $audioFormats = $formats | Where-Object {
                $_.vcodec -eq "none" -and $_.acodec -ne "none"
            }
            
            # Available resolutions and their sizes
            $availableResolutions = @()
            $videoSizes = @{}
            
            Write-Log "`nAvailable Video Resolutions:" Green
            foreach ($res in $targetResolutions) {
                # Get all formats at this resolution
                $matchingFormats = $formatsToUse | Where-Object { $_.height -eq [int]$res }
                
                if ($matchingFormats -and $matchingFormats.Count -gt 0) {
                    # Sort by quality (prefer higher bitrate)
                    $match = $matchingFormats | Sort-Object tbr -Descending | Select-Object -First 1
                    $availableResolutions += [int]$res
                    
                    # Store the format ID for later use
                    $formatIds[[int]$res] = $match.format_id
                    
                    $size = $null
                    if ($match.filesize) {
                        $size = $match.filesize
                        $sizeMB = ConvertTo-MB $size
                    } elseif ($match.filesize_approx) {
                        $size = $match.filesize_approx
                        $sizeMB = ConvertTo-MB $size
                    } else {
                        $bitrate = $match.tbr  # Total bitrate in kbps
                        # Make sure we're passing a proper number
                        if ($bitrate -ne $null) {
                            $bitrateDbl = [double]$bitrate
                            $size = Estimate-FileSize $bitrateDbl $duration
                            $sizeMB = ConvertTo-MB $size
                        } else {
                            $sizeMB = "N/A"
                        }
                    }
                    
                    # Add codec and audio info if available
                    $formatInfo = ""
                    if ($match.vcodec -and $match.vcodec -ne "none") {
                        $vcodecShort = $match.vcodec.Split('.')[0]
                        $formatInfo = " [$vcodecShort"
                        
                        # Add audio info
                        if ($match.acodec -and $match.acodec -ne "none") {
                            $acodecShort = $match.acodec.Split('.')[0]
                            $formatInfo += "+$acodecShort"
                        } else {
                            $formatInfo += ", no audio"
                        }
                        
                        if ($match.tbr) {
                            $formatInfo += ", ~$([math]::Round($match.tbr))kbps"
                        }
                        $formatInfo += "]"
                    }
                    
                    $videoSizes[[int]$res] = $size
                    $formatType = if ($match.acodec -ne "none") { "Video+Audio" } else { "Video only" }
                    $formatExt = if ($match.ext) { $match.ext.ToUpper() } else { "MP4" }
                    Write-Log "OK $formatExt - ${res}p available ($sizeMB)$formatInfo [ID: $($match.format_id)] - $formatType" Green
                } else {
                    Write-Log "X ${res}p not available" Yellow
                }
            }
            
            # Available audio bitrates and their sizes
            $availableAudioBitrates = @()
            $audioSizes = @{}
            
            Write-Log "`nAvailable MP3 Audio Qualities (estimated from streams):" Green
            foreach ($bitrate in $targetBitrates) {
                $abr = [int]$bitrate
                $match = $audioFormats | Where-Object { $_.abr -ge ($abr - 10) -and $_.abr -le ($abr + 10) } | Sort-Object abr -Descending | Select-Object -First 1
                if ($match) {
                    $availableAudioBitrates += [int]$bitrate
                    $actual = [math]::Round($match.abr)
                    
                    $size = $null
                    if ($match.filesize) {
                        $size = $match.filesize
                        $sizeMB = ConvertTo-MB $size
                    } elseif ($match.filesize_approx) {
                        $size = $match.filesize_approx
                        $sizeMB = ConvertTo-MB $size
                    } else {
                        # Make sure we're passing a proper number
                        $actualBitrate = [double]$actual
                        $size = Estimate-FileSize $actualBitrate $duration
                        $sizeMB = ConvertTo-MB $size
                    }
                    
                    $audioSizes[[int]$bitrate] = $size
                    $formatExt = if ($match.ext) { $match.ext.ToUpper() } else { "M4A" }
                    Write-Log "OK $formatExt - ${bitrate}kbps available (actual: ${actual}kbps, $sizeMB) [ID: $($match.format_id)]" Green
                } else {
                    # If no exact match, estimate size based on bitrate
                    $bitrateInt = [int]$bitrate
                    $size = Estimate-FileSize $bitrateInt $duration
                    $sizeMB = ConvertTo-MB $size
                    $audioSizes[[int]$bitrate] = $size
                    Write-Log "OK MP3 - ${bitrate}kbps available (estimated: $sizeMB)" Green
                }
            }
            
            # Sort resolutions and bitrates
            $availableResolutions = $availableResolutions | Sort-Object -Descending
            $availableAudioBitrates = $availableAudioBitrates | Sort-Object -Descending
            
            return @{
                Resolutions = $availableResolutions
                AudioBitrates = $availableAudioBitrates
                VideoSizes = $videoSizes
                AudioSizes = $audioSizes
                FormatIds = $formatIds
                Duration = $duration
            }
        }
        catch {
            Write-Log "Error parsing video information: $($_.Exception.Message)" Yellow
            # Return standard resolutions as fallback
            return @{
                Resolutions = @(2160, 1440, 1080, 720, 480, 360, 240, 144)
                AudioBitrates = @(320, 256, 192, 128)
                VideoSizes = @{}
                AudioSizes = @{}
                Duration = 0
            }
        }
    }
    catch {
        Write-Log "Error checking available formats: $($_.Exception.Message)" Yellow
        # Return standard resolutions as fallback
        return @{
            Resolutions = @(2160, 1440, 1080, 720, 480, 360, 240, 144)
            AudioBitrates = @(320, 256, 192, 128)
            VideoSizes = @{}
            AudioSizes = @{}
            Duration = 0
        }
    }
}

# Function to get available resolutions (for backward compatibility)
function Get-AvailableResolutions {
    param (
        [string]$Url,
        [int]$TimeoutSeconds = 30
    )
    
    $formats = Get-AvailableFormats -Url $Url -TimeoutSeconds $TimeoutSeconds
    return $formats.Resolutions
}

# Function to get the best available resolution at or below the requested one
function Get-BestAvailableResolution {
    param (
        [int]$RequestedResolution,
        [array]$AvailableResolutions
    )
    
    # Check if the array is null or empty
    if ($null -eq $AvailableResolutions -or $AvailableResolutions.Count -eq 0) {
        Write-Log "No available resolutions found. This might be a YouTube Short or special format video." Yellow
        # Return a default resolution for YouTube Shorts (typically 1080p or 720p)
        return 720
    }
    
    # Sort resolutions in descending order
    $AvailableResolutions = $AvailableResolutions | Sort-Object -Descending
    
    # Find the highest resolution that is <= requested resolution
    foreach ($res in $AvailableResolutions) {
        if ($res -le $RequestedResolution) {
            return $res
        }
    }
    
    # If we get here, all available resolutions are higher than requested
    # Return the lowest available resolution
    return $AvailableResolutions[-1]
}

# Detect hardware acceleration if enabled
$hwAccel = $null
if ($config.EnableHWAccel -eq $true) {
    $hwAccel = Get-BestHWAccel
    if ($hwAccel) {
        Write-Log "Hardware acceleration enabled: Using $hwAccel for faster processing" Green
    } else {
        Write-Log "Hardware acceleration not available or not detected, using software encoding" Yellow
    }
} else {
    Write-Log "Hardware acceleration disabled in config" Yellow
}

# Main logic
$choice = Show-Menu
try {
    switch ($choice) {
        "1" {
            # Get user's requested resolution
            $requestedHeight = Get-Resolution
            if (-not $requestedHeight) { throw "Invalid resolution choice" }
            
            # Check available formats and sizes
            Write-Log "Checking available formats and sizes (this may take a few seconds)..." Cyan
            $formatInfo = Get-AvailableFormats -Url $url
            
            # Check if this might be a YouTube Short or special format video
            $isShort = $false
            if ($null -eq $formatInfo.Resolutions -or $formatInfo.Resolutions.Count -eq 0) {
                Write-Log "This appears to be a YouTube Short or special format video." Yellow
                Write-Log "Using default format selection for Shorts..." Yellow
                $isShort = $true
                $actualHeight = 720 # Default height for Shorts
            } else {
                # Get the best available resolution at or below the requested one
                $actualHeight = Get-BestAvailableResolution -RequestedResolution $requestedHeight -AvailableResolutions $formatInfo.Resolutions
            }
            
            # Get estimated file size if available
            $estimatedSize = "Unknown"
            if ($formatInfo.VideoSizes.ContainsKey($actualHeight)) {
                $estimatedSize = ConvertTo-MB $formatInfo.VideoSizes[$actualHeight]
            }
            
            # Show size information
            Write-Log "Selected resolution: ${actualHeight}p (Estimated size: $estimatedSize)" Cyan
            
            if ($actualHeight -ne $requestedHeight) {
                Write-Log "Requested ${requestedHeight}p is not available. Using best available resolution: ${actualHeight}p" Yellow
            }
            
            # For video with audio, we need to ensure we get both video and audio
            # We can't just use the format ID directly as it might be video-only
            $formatId = ""
            if ($isShort) {
                # For YouTube Shorts, use a more flexible format string
                $format = "best/bestvideo+bestaudio"
                Write-Log "Using YouTube Shorts format selector: best/bestvideo+bestaudio" Yellow
            }
            elseif ($formatInfo.FormatIds -and $formatInfo.FormatIds.ContainsKey($actualHeight)) {
                $formatId = $formatInfo.FormatIds[$actualHeight]
                # For video with audio, we need to add the best audio stream
                $format = "$formatId+bestaudio/best[height<=$actualHeight]"
                Write-Log "Using format: $formatId+bestaudio for ${actualHeight}p" Green
            } else {
                $format = "best[height<=$actualHeight]/bestvideo[height<=$actualHeight]+bestaudio"
                Write-Log "Using format selector: best[height<=$actualHeight]" Yellow
            }
            
            $output = Join-Path $fullPath "%(title)s_${actualHeight}p_%(upload_date>%Y%m%d)s.%(ext)s"
            Write-Log "Downloading video with audio (${actualHeight}p MP4)..." Green
            
            # Get ffmpeg arguments for hardware acceleration with mobile optimization
            $ffmpegArgs = Get-FFmpegArgs -HWAccel $hwAccel -MediaType "video" -MobileOptimized $true
            
            # Add specific post-processing arguments optimized for mobile playback with better compatibility
            $postProcessArgs = "-threads 8 -preset medium -movflags faststart+frag_keyframe+empty_moov -max_muxing_queue_size 4096 -pix_fmt yuv420p"
            Write-Log "Using mobile-optimized settings for smooth playback on all devices" Green
            
            # Use try-catch to handle errors
            try {
                # Use our new function to generate the command with correct parameters
                $ytDlpCmd = Get-YtDlpCommand -Format $format -Output $output -Url $url -FfmpegArgs $ffmpegArgs -PostProcessArgs $postProcessArgs -PlaylistFlag $playlistFlag -ConcurrentFragments $config.MaxConcurrentFragments -BufferSize $config.BufferSize -SubtitleLanguage $config.SubtitleLanguage
                
                # Execute the command
                Invoke-Expression $ytDlpCmd
                Write-Log "Video download completed successfully!" Green
            }
            catch {
                # If the error is about the srt parameter, retry with the correct format
                if ($_.Exception.Message -match "srt") {
                    Write-Log "Retrying with corrected subtitle parameter..." Yellow
                    $ytDlpCmd = Get-YtDlpCommand -Format $format -Output $output -Url $url -FfmpegArgs $ffmpegArgs -PostProcessArgs $postProcessArgs -PlaylistFlag $playlistFlag -ConcurrentFragments $config.MaxConcurrentFragments -BufferSize $config.BufferSize -SubtitleLanguage $config.SubtitleLanguage
                    Invoke-Expression $ytDlpCmd
                    Write-Log "Video download completed successfully!" Green
                }
                # If the error is about format not being available
                elseif ($_.Exception.Message -match "Requested format is not available") {
                    Write-Log "The requested format is not available. Trying with best available format..." Yellow
                    $ytDlpCmd = Get-YtDlpCommand -Format "best[ext=mp4]/bestvideo[ext=mp4]+bestaudio[ext=m4a]" -Output $output -Url $url -FfmpegArgs $ffmpegArgs -PostProcessArgs $postProcessArgs -PlaylistFlag $playlistFlag -ConcurrentFragments $config.MaxConcurrentFragments -BufferSize $config.BufferSize -SubtitleLanguage $config.SubtitleLanguage
                    Invoke-Expression $ytDlpCmd
                    Write-Log "Video download completed successfully!" Green
                }
                # If there's an error with the post-processing arguments or output files
                elseif ($_.Exception.Message -match "post-process|ppa|Error opening output files|Invalid argument") {
                    Write-Log "Issue with post-processing arguments or output file. Retrying with simplified settings..." Yellow
                    
                    # First try with no post-processing arguments
                    $ytDlpCmd = Get-YtDlpCommand -Format $format -Output $output -Url $url -FfmpegArgs "-c copy" -PostProcessArgs "" -PlaylistFlag $playlistFlag -ConcurrentFragments $config.MaxConcurrentFragments -BufferSize $config.BufferSize -SubtitleLanguage $config.SubtitleLanguage
                    
                    try {
                        Invoke-Expression $ytDlpCmd
                        Write-Log "Video download completed successfully with simplified settings!" Green
                    }
                    catch {
                        # If that fails, try with the most basic settings possible
                        Write-Log "Still having issues. Trying with basic format and no special encoding..." Yellow
                        $basicOutput = Join-Path $fullPath "%(title)s_basic_%(upload_date>%Y%m%d)s.mp4"
                        $basicCmd = "yt-dlp.exe -f 'best[ext=mp4]/best' --merge-output-format mp4 $playlistFlag --retries 10 --fragment-retries 10 --continue --no-part -o `"$basicOutput`" `"$url`""
                        Invoke-Expression $basicCmd
                        Write-Log "Video download completed with basic settings!" Green
                    }
                }
                # If there's a connection timeout or network error
                elseif ($_.Exception.Message -match "timed out|timeout|connection|reset|refused|network|HTTPSConnectionPool") {
                    Write-Log "Network connection issue detected. Retrying with more reliable settings..." Yellow
                    
                    # Use more conservative network settings
                    $ytDlpCmd = Get-YtDlpCommand -Format $format -Output $output -Url $url -FfmpegArgs $ffmpegArgs -PostProcessArgs "" -PlaylistFlag $playlistFlag -ConcurrentFragments 4 -BufferSize "4M" -SubtitleLanguage $config.SubtitleLanguage
                    
                    # Add network reliability flags
                    $ytDlpCmd = $ytDlpCmd.Replace("--no-part", "--force-ipv4 --no-part")
                    $ytDlpCmd = $ytDlpCmd.Replace("--retries 20", "--retries 30 --retry-sleep 10")
                    
                    Write-Log "Using more conservative network settings to handle connection issues..." Yellow
                    
                    # Execute the command
                    Invoke-Expression $ytDlpCmd
                    Write-Log "Video download completed successfully!" Green
                }
                # If there's an HTTP 416 error (Requested range not satisfiable)
                elseif ($_.Exception.Message -match "HTTP Error 416|Requested range not satisfiable") {
                    Write-Log "HTTP 416 error detected. Retrying with single-fragment download..." Yellow
                    
                    # Disable concurrent fragments and use a smaller buffer size
                    $ytDlpCmd = Get-YtDlpCommand -Format $format -Output $output -Url $url -FfmpegArgs $ffmpegArgs -PostProcessArgs "" -PlaylistFlag $playlistFlag -ConcurrentFragments 1 -BufferSize "8M" -SubtitleLanguage $config.SubtitleLanguage
                    
                    # Add the force-generic-extractor flag to avoid range requests
                    $ytDlpCmd = $ytDlpCmd.Replace("--no-part", "--force-generic-extractor --no-part")
                    
                    # Execute the command
                    Invoke-Expression $ytDlpCmd
                    Write-Log "Video download completed successfully!" Green
                }
                else {
                    throw
                }
            }
        }
        "2" {
            # Get user's requested resolution
            $requestedHeight = Get-Resolution
            if (-not $requestedHeight) { throw "Invalid resolution choice" }
            
            # Check available formats and sizes
            Write-Log "Checking available formats and sizes (this may take a few seconds)..." Cyan
            $formatInfo = Get-AvailableFormats -Url $url
            
            # Check if this might be a YouTube Short or special format video
            $isShort = $false
            if ($null -eq $formatInfo.Resolutions -or $formatInfo.Resolutions.Count -eq 0) {
                Write-Log "This appears to be a YouTube Short or special format video." Yellow
                Write-Log "Using default format selection for Shorts..." Yellow
                $isShort = $true
                $actualHeight = 720 # Default height for Shorts
            } else {
                # Get the best available resolution at or below the requested one
                $actualHeight = Get-BestAvailableResolution -RequestedResolution $requestedHeight -AvailableResolutions $formatInfo.Resolutions
            }
            
            # Get estimated file size if available
            $estimatedSize = "Unknown"
            if ($formatInfo.VideoSizes -and $formatInfo.VideoSizes.ContainsKey($actualHeight)) {
                $estimatedSize = ConvertTo-MB $formatInfo.VideoSizes[$actualHeight]
            }
            
            # Show size information
            Write-Log "Selected resolution: ${actualHeight}p (Estimated size: $estimatedSize)" Cyan
            
            if ($actualHeight -ne $requestedHeight) {
                Write-Log "Requested ${requestedHeight}p is not available. Using best available resolution: ${actualHeight}p" Yellow
            }
            
            # Check if we have a specific format ID for this resolution
            $formatId = ""
            if ($isShort) {
                # For YouTube Shorts, use a more flexible format string
                $format = "bestvideo[ext=mp4]/bestvideo"
                Write-Log "Using YouTube Shorts format selector: bestvideo[ext=mp4]/bestvideo" Yellow
            } 
            elseif ($formatInfo.FormatIds -and $formatInfo.FormatIds.ContainsKey($actualHeight)) {
                $formatId = $formatInfo.FormatIds[$actualHeight]
                $format = $formatId
                Write-Log "Using exact format ID: $formatId for ${actualHeight}p" Green
            } else {
                $format = "bestvideo[ext=mp4][height<=$actualHeight]"
                Write-Log "Using format selector: bestvideo[ext=mp4][height<=$actualHeight]" Yellow
            }
            
            $output = Join-Path $videoPath "%(title)s_${actualHeight}p_video_%(upload_date>%Y%m%d)s.%(ext)s"
            Write-Log "Downloading video only (${actualHeight}p MP4)..." Green
            
            # Get ffmpeg arguments for hardware acceleration with mobile optimization
            $ffmpegArgs = Get-FFmpegArgs -HWAccel $hwAccel -MediaType "video" -MobileOptimized $true
            
            # Add specific post-processing arguments optimized for mobile playback with better compatibility
            $postProcessArgs = "-threads 8 -preset medium -movflags faststart+frag_keyframe+empty_moov -max_muxing_queue_size 4096 -pix_fmt yuv420p"
            Write-Log "Using mobile-optimized settings for smooth playback on all devices" Green
            
            try {
                # Use our new function to generate the command with correct parameters
                $ytDlpCmd = Get-YtDlpCommand -Format $format -Output $output -Url $url -FfmpegArgs $ffmpegArgs -PostProcessArgs $postProcessArgs -PlaylistFlag $playlistFlag -ConcurrentFragments $config.MaxConcurrentFragments -BufferSize $config.BufferSize -SubtitleLanguage $config.SubtitleLanguage -VideoOnly
                
                # Execute the command
                Invoke-Expression $ytDlpCmd
                Write-Log "Video download completed successfully!" Green
            }
            catch {
                if ($_.Exception.Message -match "srt") {
                    Write-Log "Retrying with corrected subtitle parameter..." Yellow
                    $ytDlpCmd = Get-YtDlpCommand -Format "bestvideo[ext=mp4][height<=$actualHeight]" -Output $output -Url $url -FfmpegArgs $ffmpegArgs -PostProcessArgs $postProcessArgs -PlaylistFlag $playlistFlag -ConcurrentFragments $config.MaxConcurrentFragments -BufferSize $config.BufferSize -SubtitleLanguage $config.SubtitleLanguage -VideoOnly
                    Invoke-Expression $ytDlpCmd
                    Write-Log "Video download completed successfully!" Green
                }
                # If the error is about format not being available
                elseif ($_.Exception.Message -match "Requested format is not available") {
                    Write-Log "The requested format is not available. Trying with best available format..." Yellow
                    $ytDlpCmd = Get-YtDlpCommand -Format "bestvideo[ext=mp4]" -Output $output -Url $url -FfmpegArgs $ffmpegArgs -PostProcessArgs $postProcessArgs -PlaylistFlag $playlistFlag -ConcurrentFragments $config.MaxConcurrentFragments -BufferSize $config.BufferSize -SubtitleLanguage $config.SubtitleLanguage -VideoOnly
                    Invoke-Expression $ytDlpCmd
                    Write-Log "Video download completed successfully!" Green
                }
                # If there's an error with the post-processing arguments or output files
                elseif ($_.Exception.Message -match "post-process|ppa|Error opening output files|Invalid argument") {
                    Write-Log "Issue with post-processing arguments or output file. Retrying with simplified settings..." Yellow
                    
                    # First try with no post-processing arguments
                    $ytDlpCmd = Get-YtDlpCommand -Format $format -Output $output -Url $url -FfmpegArgs "-c copy" -PostProcessArgs "" -PlaylistFlag $playlistFlag -ConcurrentFragments $config.MaxConcurrentFragments -BufferSize $config.BufferSize -SubtitleLanguage $config.SubtitleLanguage -VideoOnly
                    
                    try {
                        Invoke-Expression $ytDlpCmd
                        Write-Log "Video download completed successfully with simplified settings!" Green
                    }
                    catch {
                        # If that fails, try with the most basic settings possible
                        Write-Log "Still having issues. Trying with basic format and no special encoding..." Yellow
                        $basicOutput = Join-Path $videoPath "%(title)s_basic_video_%(upload_date>%Y%m%d)s.mp4"
                        $basicCmd = "yt-dlp.exe -f 'bestvideo[ext=mp4]' $playlistFlag --retries 10 --fragment-retries 10 --continue --no-part -o `"$basicOutput`" `"$url`""
                        Invoke-Expression $basicCmd
                        Write-Log "Video download completed with basic settings!" Green
                    }
                }
                # If there's a connection timeout or network error
                elseif ($_.Exception.Message -match "timed out|timeout|connection|reset|refused|network|HTTPSConnectionPool") {
                    Write-Log "Network connection issue detected. Retrying with more reliable settings..." Yellow
                    
                    # Use more conservative network settings
                    $ytDlpCmd = Get-YtDlpCommand -Format $format -Output $output -Url $url -FfmpegArgs $ffmpegArgs -PostProcessArgs "" -PlaylistFlag $playlistFlag -ConcurrentFragments 4 -BufferSize "4M" -SubtitleLanguage $config.SubtitleLanguage -VideoOnly
                    
                    # Add network reliability flags
                    $ytDlpCmd = $ytDlpCmd.Replace("--no-part", "--force-ipv4 --no-part")
                    $ytDlpCmd = $ytDlpCmd.Replace("--retries 20", "--retries 30 --retry-sleep 10")
                    
                    Write-Log "Using more conservative network settings to handle connection issues..." Yellow
                    
                    # Execute the command
                    Invoke-Expression $ytDlpCmd
                    Write-Log "Video download completed successfully!" Green
                }
                # If there's an HTTP 416 error (Requested range not satisfiable)
                elseif ($_.Exception.Message -match "HTTP Error 416|Requested range not satisfiable") {
                    Write-Log "HTTP 416 error detected. Retrying with single-fragment download..." Yellow
                    
                    # Disable concurrent fragments and use a smaller buffer size
                    $ytDlpCmd = Get-YtDlpCommand -Format $format -Output $output -Url $url -FfmpegArgs $ffmpegArgs -PostProcessArgs "" -PlaylistFlag $playlistFlag -ConcurrentFragments 1 -BufferSize "8M" -SubtitleLanguage $config.SubtitleLanguage -VideoOnly
                    
                    # Add the force-generic-extractor flag to avoid range requests
                    $ytDlpCmd = $ytDlpCmd.Replace("--no-part", "--force-generic-extractor --no-part")
                    
                    # Execute the command
                    Invoke-Expression $ytDlpCmd
                    Write-Log "Video download completed successfully!" Green
                }
                else {
                    throw
                }
            }
        }
        "3" {
            # Check available formats and sizes first
            Write-Log "Checking available formats and sizes (this may take a few seconds)..." Cyan
            $formatInfo = Get-AvailableFormats -Url $url
            
            $qualityValues = Get-AudioQuality
            if (-not $qualityValues) { throw "Invalid audio quality choice" }
            $ytQuality, $kbps = $qualityValues
            
            # Get estimated file size if available
            $estimatedSize = "Unknown"
            if ($formatInfo.AudioSizes.ContainsKey([int]$kbps)) {
                $estimatedSize = ConvertTo-MB $formatInfo.AudioSizes[[int]$kbps]
            }
            
            # Show size information
            Write-Log "Selected audio quality: ${kbps}kbps (Estimated size: $estimatedSize)" Cyan
            
            # Force .mp3 extension to avoid container issues
            $output = Join-Path $audioPath "%(title)s_mp3_${kbps}kbps_%(upload_date>%Y%m%d)s.mp3"
            Write-Log "Downloading audio only (MP3 ${kbps}kbps)..." Green
            Write-Log "Using high-performance audio download with $($config.MaxConcurrentFragments) concurrent fragments..." Cyan
            
            # Get ffmpeg arguments for hardware acceleration with optimized audio settings
            $ffmpegArgs = Get-FFmpegArgs -HWAccel $hwAccel -MediaType "audio"
            
            # Add specific post-processing arguments for better audio compatibility and quality
            $postProcessArgs = "-threads 8 -preset medium -movflags faststart -af aresample=async=1:min_hard_comp=0.100000:first_pts=0 -ar 44100 -ac 2 -id3v2_version 3 -write_id3v1 1"
            
            # Increase the number of concurrent fragments specifically for audio
            $audioFragments = [math]::Min(64, $config.MaxConcurrentFragments * 2)
            Write-Log "Boosting concurrent fragments to $audioFragments for faster audio processing" Green
            
            # Increase buffer size for audio downloads
            $audioBufferSize = "32M"
            
            # Find the best audio format ID if available
            $bestAudioFormatId = ""
            $audioFormats = $formatInfo.FormatIds | Where-Object { $_ -match "audio" }
            if ($audioFormats -and $audioFormats.Count -gt 0) {
                $bestAudioFormatId = $audioFormats[0]
                Write-Log "Using optimized audio format: $bestAudioFormatId" Green
            }
            
            # Check if MP3 is directly available to avoid conversion
            $mp3Available = $formatInfo.FormatIds | Where-Object { $_ -match "audio.*mp3" }
            $mp3Format = $null
            
            if ($mp3Available) {
                $mp3Format = $mp3Available[0]
                Write-Log "MP3 format directly available! This will be much faster as no conversion is needed." Green
            }
            
            # Check if only DASH m4a formats are available and warn the user
            $dashM4aOnly = $true
            $audioFormats = $formatInfo.FormatIds | Where-Object { $_ -match "audio" }
            foreach ($format in $audioFormats) {
                if ($format -notmatch "m4a") {
                    $dashM4aOnly = $false
                    break
                }
            }
            
            if ($dashM4aOnly -and $audioFormats.Count -gt 0) {
                Write-Log "NOTE: Only DASH m4a audio formats are available for this video." Yellow
                Write-Log "The script will automatically convert to MP3, but this may take longer." Yellow
            }
            
            # Construct format string - prioritize audio-only formats
            # For faster processing, prefer mp3 formats if available to avoid conversion
            # Avoid DASH m4a containers which cause warnings and compatibility issues
            $formatString = if ($mp3Format) {
                # If MP3 is directly available, use it to avoid conversion
                "$mp3Format"
            } elseif ($bestAudioFormatId) {
                "$bestAudioFormatId"
            } else {
                # Prioritize non-DASH formats and formats that don't require conversion
                # Avoid m4a formats when possible to prevent DASH container warnings
                "bestaudio[ext=mp3]/bestaudio[ext=webm]/bestaudio[ext=opus]/bestaudio[ext!=m4a]/bestaudio"
            }
            
            # If MP3 is directly available, we can skip the extraction step
            $skipExtraction = $mp3Format -ne $null
            
            Write-Log "Using optimized audio extraction and conversion settings" Green
            
            try {
                # Use optimized settings for audio downloads:
                # 1. Skip subtitle downloads for audio-only (they're rarely needed and slow things down)
                # 2. Use increased concurrent fragments
                # 3. Use larger buffer size
                # 4. Use specific audio format selection to avoid video processing
                # 5. Add --no-check-certificate to avoid SSL verification delays
                # 6. Add --no-part to avoid creating temporary .part files
                # 7. Add --no-mtime to skip modification time setting
                # 8. Add --extract-audio to directly extract audio without separate conversion step
                # 9. Add --ppa to pass post-processing arguments to ffmpeg
                
                if ($mp3Format) {
                    # If MP3 is directly available, download it directly without conversion
                    # This is much faster as it avoids the entire conversion process
                    Write-Log "Using direct MP3 download (no conversion needed) - this will be much faster!" Green
                    
                    # Generate command for direct MP3 download (no extraction needed)
                    $ytDlpCmd = Get-YtDlpCommand -Format $formatString -Output $output -Url $url -FfmpegArgs $ffmpegArgs -PostProcessArgs "" -PlaylistFlag $playlistFlag -ConcurrentFragments $audioFragments -BufferSize $audioBufferSize -SkipSubtitles
                    
                    # Add the --no-extract-audio flag to avoid unnecessary processing
                    $ytDlpCmd = $ytDlpCmd.Replace("-f $formatString", "-f $formatString --no-extract-audio")
                    
                    # Execute the command
                    Invoke-Expression $ytDlpCmd
                    Write-Log "Audio download completed successfully!" Green
                } else {
                    # If MP3 is not directly available, we need to convert from another format
                    Write-Log "Using high-performance audio extraction with optimized settings" Green
                    
                    # Generate command for audio extraction and conversion
                    $ytDlpCmd = Get-YtDlpCommand -Format $formatString -Output $output -Url $url -FfmpegArgs $ffmpegArgs -PostProcessArgs $postProcessArgs -PlaylistFlag $playlistFlag -ConcurrentFragments $audioFragments -BufferSize $audioBufferSize -AudioOnly -AudioQuality $ytQuality -SkipSubtitles
                    
                    # Execute the command
                    Invoke-Expression $ytDlpCmd
                    Write-Log "Audio download completed successfully!" Green
                }
            }
            catch {
                # If the error is about format not being available
                if ($_.Exception.Message -match "Requested format is not available") {
                    Write-Log "The requested format is not available. Trying with best available format..." Yellow
                    
                    # Generate command for audio extraction with best available format
                    $ytDlpCmd = Get-YtDlpCommand -Format "bestaudio" -Output $output -Url $url -FfmpegArgs $ffmpegArgs -PostProcessArgs $postProcessArgs -PlaylistFlag $playlistFlag -ConcurrentFragments $audioFragments -BufferSize $audioBufferSize -AudioOnly -AudioQuality $ytQuality -SkipSubtitles
                    
                    # Execute the command
                    Invoke-Expression $ytDlpCmd
                    Write-Log "Audio download completed successfully!" Green
                }
                # If there's an error with the post-processing arguments
                elseif ($_.Exception.Message -match "post-process|postprocessor") {
                    Write-Log "Issue with post-processing arguments. Retrying with simplified settings..." Yellow
                    
                    # Generate command without post-processing arguments
                    $ytDlpCmd = Get-YtDlpCommand -Format "bestaudio" -Output $output -Url $url -FfmpegArgs $ffmpegArgs -PostProcessArgs "" -PlaylistFlag $playlistFlag -ConcurrentFragments $audioFragments -BufferSize $audioBufferSize -AudioOnly -AudioQuality $ytQuality -SkipSubtitles
                    
                    # Execute the command
                    Invoke-Expression $ytDlpCmd
                    Write-Log "Audio download completed successfully!" Green
                }
                # If there's an error with the M4A to MP3 conversion or output files
                elseif ($_.Exception.Message -match "Error opening output files|Invalid argument|FixupM4a") {
                    Write-Log "Issue with audio conversion or output files. Using direct ffmpeg conversion..." Yellow
                    
                    try {
                        # First try with simplified settings
                        $simpleCmd = "yt-dlp.exe -f 'bestaudio' --extract-audio --audio-format mp3 --audio-quality $ytQuality $playlistFlag --retries 10 --continue --progress --newline -o `"$output`" `"$url`""
                        Invoke-Expression $simpleCmd
                        Write-Log "Audio download completed with simplified settings!" Green
                    }
                    catch {
                        Write-Log "Still having issues. Trying with two-step conversion process..." Yellow
                        
                        # First download the audio in its original format
                        $tempOutput = Join-Path $audioPath "%(title)s_temp_%(upload_date>%Y%m%d)s.%(ext)s"
                        $tempCmd = "yt-dlp.exe -f bestaudio --no-extract-audio $playlistFlag --ffmpeg-location $ffmpegPath --retries 10 --continue --progress --newline -o `"$tempOutput`" `"$url`""
                        Invoke-Expression $tempCmd
                        
                        # Get the downloaded file path
                        $downloadedFile = Get-ChildItem -Path $audioPath -Filter "*_temp_*" | Select-Object -First 1
                    }
                    
                    if ($downloadedFile) {
                        $finalOutput = $output -replace "%\(title\)s", $downloadedFile.BaseName.Split('_')[0]
                        $finalOutput = $finalOutput -replace "%\(upload_date>%Y%m%d\)s", (Get-Date -Format "yyyyMMdd")
                        
                        # Use ffmpeg directly to convert to MP3
                        Write-Log "Converting $($downloadedFile.Name) to MP3 format..." Yellow
                        & $ffmpegPath -i "$($downloadedFile.FullName)" -c:a libmp3lame -q:a 2 -y "$finalOutput"
                        
                        # Remove the temporary file
                        Remove-Item $downloadedFile.FullName -Force
                        Write-Log "Audio conversion completed successfully!" Green
                    } else {
                        Write-Log "Could not find downloaded file for conversion." Red
                        throw "Conversion failed"
                    }
                }
                # If there's an error with the extraction
                elseif ($_.Exception.Message -match "extract|conversion|ffmpeg") {
                    Write-Log "Issue with audio extraction. Trying with basic settings..." Yellow
                    
                    # Use minimal settings for maximum compatibility
                    $basicCmd = "yt-dlp.exe -f bestaudio -x --audio-format mp3 --audio-quality $ytQuality $playlistFlag --ffmpeg-location $ffmpegPath --retries 10 --continue --progress --newline -o `"$output`" `"$url`""
                    Invoke-Expression $basicCmd
                    Write-Log "Audio download completed successfully!" Green
                }
                # If there's a connection timeout or network error
                elseif ($_.Exception.Message -match "timed out|timeout|connection|reset|refused|network|HTTPSConnectionPool") {
                    Write-Log "Network connection issue detected. Retrying with more reliable settings..." Yellow
                    
                    # Use more conservative network settings
                    $ytDlpCmd = Get-YtDlpCommand -Format "bestaudio" -Output $output -Url $url -FfmpegArgs $ffmpegArgs -PostProcessArgs "" -PlaylistFlag $playlistFlag -ConcurrentFragments 4 -BufferSize "4M" -AudioOnly -AudioQuality $ytQuality -SkipSubtitles
                    
                    # Add network reliability flags
                    $ytDlpCmd = $ytDlpCmd.Replace("--no-part", "--force-ipv4 --no-part")
                    $ytDlpCmd = $ytDlpCmd.Replace("--retries 20", "--retries 30 --retry-sleep 10")
                    
                    Write-Log "Using more conservative network settings to handle connection issues..." Yellow
                    
                    # Execute the command
                    Invoke-Expression $ytDlpCmd
                    Write-Log "Audio download completed successfully!" Green
                }
                # If there's an HTTP 416 error (Requested range not satisfiable)
                elseif ($_.Exception.Message -match "HTTP Error 416|Requested range not satisfiable") {
                    Write-Log "HTTP 416 error detected. Retrying with single-fragment download..." Yellow
                    
                    # Disable concurrent fragments and use a smaller buffer size
                    $ytDlpCmd = Get-YtDlpCommand -Format "bestaudio" -Output $output -Url $url -FfmpegArgs $ffmpegArgs -PostProcessArgs "" -PlaylistFlag $playlistFlag -ConcurrentFragments 1 -BufferSize "8M" -AudioOnly -AudioQuality $ytQuality -SkipSubtitles
                    
                    # Add the --no-part flag to avoid partial downloads
                    $ytDlpCmd = $ytDlpCmd.Replace("--no-part", "--force-generic-extractor --no-part")
                    
                    # Execute the command
                    Invoke-Expression $ytDlpCmd
                    Write-Log "Audio download completed successfully!" Green
                }
                # If there's an SSL error
                elseif ($_.Exception.Message -match "SSL") {
                    Write-Log "SSL verification issue. Retrying with standard settings..." Yellow
                    
                    # Generate command without SSL verification
                    $ytDlpCmd = Get-YtDlpCommand -Format "bestaudio" -Output $output -Url $url -FfmpegArgs $ffmpegArgs -PostProcessArgs "" -PlaylistFlag $playlistFlag -ConcurrentFragments $config.MaxConcurrentFragments -BufferSize $config.BufferSize -AudioOnly -AudioQuality $ytQuality -SkipSubtitles
                    
                    # Remove the no-check-certificate flag
                    $ytDlpCmd = $ytDlpCmd.Replace("--no-check-certificate", "")
                    
                    # Execute the command
                    Invoke-Expression $ytDlpCmd
                    Write-Log "Audio download completed successfully!" Green
                }
                else {
                    throw
                }
            }
        }
        "4" {
            do {
                $subLang = Read-Host "Enter subtitle language code (e.g. en, fr, ar, sw)"
                if (-not $subLang) { 
                    $subLang = "en" 
                    Write-Log "No language specified, using default: en (English)" Yellow
                }
            } until ($subLang)
            
            # Extract the video ID from the URL to handle playlists properly
            $videoId = ""
            if ($url -match "youtu\.be\/([a-zA-Z0-9_-]+)") {
                $videoId = $matches[1]
            } elseif ($url -match "youtube\.com\/watch\?v=([a-zA-Z0-9_-]+)") {
                $videoId = $matches[1]
            }
            
            # If we found a video ID, use it directly to avoid playlist issues
            if ($videoId) {
                $directUrl = "https://www.youtube.com/watch?v=$videoId"
                Write-Log "Using direct video URL: $directUrl" Cyan
            } else {
                $directUrl = $url
            }
            
            # Check if subtitles are available before attempting to download
            if (Test-SubtitlesAvailable -Url $directUrl -Language $subLang) {
                # Use double quotes for the output path to avoid the "c#" path issue
                $escapedSubsPath = $subsPath -replace '\\', '\\'
                $output = "`"$escapedSubsPath\\%(title)s_subs_%(upload_date>%Y%m%d)s.%(ext)s`""
                Write-Log "Downloading subtitles (language: $subLang, .srt format)..." Green
                
                try {
                    # Always use --no-playlist to avoid the "Fixed output name but more than one file to download" error
                    $safePlaylistFlag = "--no-playlist"
                    
                    # Use a timeout job to prevent hanging
                    $job = Start-Job -ScriptBlock {
                        param($ytdlpPath, $url, $subLang, $playlistFlag, $output)
                        # Use --sub-format vtt to ensure we get the WebVTT format which is more reliable
                        # Add --force-overwrites to ensure we get fresh subtitles
                        & $ytdlpPath --skip-download --write-sub --write-auto-sub --sub-lang $subLang --sub-format vtt --convert-subs=srt --force-overwrites $playlistFlag -o $output $url
                    } -ArgumentList "yt-dlp.exe", $directUrl, $subLang, $safePlaylistFlag, $output
                    
                    # Show a progress indicator while waiting
                    $spinner = @('|', '/', '-', '\')
                    $i = 0
                    $timeout = 30 # 30 seconds timeout (reduced from 60)
                    $start = Get-Date
                    
                    Write-Host "Downloading subtitles " -NoNewline
                    
                    while ((Get-Job -Id $job.Id).State -eq "Running") {
                        Write-Host "`b$($spinner[$i % $spinner.Length])" -NoNewline
                        Start-Sleep -Milliseconds 200
                        $i++
                        
                        # Check for timeout
                        if ((New-TimeSpan -Start $start -End (Get-Date)).TotalSeconds -gt $timeout) {
                            Write-Host "`b "
                            Write-Log "Subtitle download is taking too long. Attempting to force completion..." Yellow
                            Stop-Job -Job $job
                            break
                        }
                    }
                    
                    Write-Host "`b " # Clear the spinner
                    
                    # Get the job output
                    if ((Get-Job -Id $job.Id).State -eq "Completed") {
                        $jobOutput = Receive-Job -Job $job
                        # Check if the output contains error messages about locked subtitles
                        if ($jobOutput -match "are locked" -or $jobOutput -match "not available") {
                            Write-Log "Subtitles are locked or not available for this video." Yellow
                            Remove-Job -Job $job -Force
                            Write-Log "Some videos have subtitles that cannot be downloaded due to content owner restrictions." Yellow
                            return
                        }
                    }
                    Remove-Job -Job $job -Force
                    
                    # Verify that subtitles were actually downloaded
                    $subsFiles = Get-ChildItem -Path $subsPath -Filter "*.srt" | Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-5) }
                    if ($subsFiles -and $subsFiles.Count -gt 0) {
                        Write-Log "Subtitles downloaded successfully!" Green
                        foreach ($file in $subsFiles) {
                            Write-Log "  - $($file.Name)" Green
                        }
                    }
                    else {
                        # Try a direct download with simpler parameters
                        Write-Log "No subtitle files found. Trying alternative download method..." Yellow
                        $result = yt-dlp.exe --skip-download --write-auto-sub --sub-lang $subLang --sub-format vtt --convert-subs=srt --force-overwrites --no-check-certificate --no-warnings --no-playlist -o $output $directUrl 2>&1
                        
                        # Check for locked subtitles in the output
                        if ($result -match "are locked" -or $result -match "not available") {
                            Write-Log "Subtitles are locked or not available for this video." Yellow
                            Write-Log "Some videos have subtitles that cannot be downloaded due to content owner restrictions." Yellow
                            return
                        }
                        
                        # Check again
                        $subsFiles = Get-ChildItem -Path $subsPath -Filter "*.srt" | Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-5) }
                        if ($subsFiles -and $subsFiles.Count -gt 0) {
                            Write-Log "Subtitles downloaded successfully with alternative method!" Green
                            foreach ($file in $subsFiles) {
                                Write-Log "  - $($file.Name)" Green
                            }
                        }
                        else {
                            # Try one more approach - direct auto-caption download
                            Write-Log "Trying to download auto-generated captions..." Yellow
                            $result = yt-dlp.exe --skip-download --write-auto-sub --sub-lang $subLang --sub-format vtt --force-overwrites --no-playlist -o $output $directUrl 2>&1
                            
                            $subsFiles = Get-ChildItem -Path $subsPath -Filter "*.$subLang.*" | Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-5) }
                            if ($subsFiles -and $subsFiles.Count -gt 0) {
                                Write-Log "Auto-captions downloaded successfully!" Green
                                foreach ($file in $subsFiles) {
                                    Write-Log "  - $($file.Name)" Green
                                }
                            }
                            else {
                                Write-Log "No subtitle files were created. The subtitles may be locked or unavailable." Yellow
                                Write-Log "Some videos have subtitles that cannot be downloaded due to content owner restrictions." Yellow
                            }
                        }
                    }
                }
                catch {
                    # Check if the error message indicates locked subtitles
                    if ($_.Exception.Message -match "are locked" -or $_.Exception.Message -match "not available" -or 
                        $_.Exception.Message -match "Fixed output name but more than one file") {
                        Write-Log "Subtitles are locked or not available for this video." Yellow
                        Write-Log "Some videos have subtitles that cannot be downloaded due to content owner restrictions." Yellow
                    } else {
                        Write-Log "Error downloading subtitles: $($_.Exception.Message)" Yellow
                        Write-Log "Some videos have subtitles that cannot be downloaded due to content owner restrictions." Yellow
                    }
                }
            }
            else {
                Write-Log "No subtitles available for language: $subLang. Try another language or video." Yellow
            }
        }
        default {
            Write-Log "Invalid choice: $choice" Red
            throw "Invalid menu choice"
        }
    }
    
    Write-Log "`nOperation completed successfully!" Green
    Write-Log "Files saved to: $basePath" Green
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)" Red
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" Red
}

Write-Log "`nLog file saved to: $logFile" Cyan
Write-Log "All logs are stored in the Logs folder for future reference" Cyan
# run .\YT-MediaFetcher-v7.ps1
