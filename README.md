# YouTube Media Downloader

A powerful PowerShell script for downloading YouTube videos, audio, and subtitles with advanced format selection and quality options.

![YouTube Downloader Banner](https://i.imgur.com/XYZ123.png)

## Quick Start

### Option 1: Using the Launcher (Recommended)
1. Double-click `Launch-YTDownloader.bat` or `Launch-YTDownloader-Deluxe.bat`
2. Enter a YouTube URL
3. Choose download options
4. Wait for download to complete

### Option 2: Manual Launch
1. Open PowerShell
2. Navigate to the script directory
3. Run `.\YT-MediaFetcher-v7.ps1`
4. Enter a YouTube URL
5. Choose download options
6. Wait for download to complete

### Creating a Desktop Shortcut
1. Run `Create-Desktop-Shortcut.bat`
2. A shortcut will be created on your desktop
3. Use this shortcut to launch the downloader with a single click

## Features

- **Multiple Download Options**:
  - Video with audio (MP4)
  - Video only (MP4)
  - Audio only (MP3)
  - Subtitles only (SRT)

- **High-Performance Processing**:
  - **NEW**: Mobile-optimized video encoding for smooth playback on all devices
  - **NEW**: Direct MP3 download when available (no conversion needed)
  - **NEW**: Balanced quality and speed settings for optimal results
  - **NEW**: Optimized merging process for faster video processing
  - **NEW**: Enhanced audio conversion with specialized parameters
  - **NEW**: Increased concurrent fragments for audio downloads (up to 64)

- **GPU Acceleration**:
  - Automatically detects and utilizes GPU for faster processing
  - Supports NVIDIA (CUDA/NVENC), AMD (AMF), and Intel (QuickSync) GPUs
  - **NEW**: Mobile-optimized encoding for smooth playback on phones and tablets
  - **NEW**: GPU-specific optimizations for each hardware type
  - **NEW**: Balanced presets for both quality and speed
  - Reduces CPU usage during downloads and conversions

- **Advanced Format Detection**:
  - Automatically detects available video resolutions
  - Shows estimated file sizes before downloading
  - Displays detailed codec and bitrate information
  - Identifies which formats include audio
  - **NEW**: Detects when MP3 format is directly available

- **Quality Selection**:
  - Choose from multiple video resolutions (144p to 4K)
  - Select MP3 audio quality (128kbps to 320kbps)
  - Automatically selects best available quality if requested resolution isn't available

- **Organized Downloads**:
  - Automatically sorts downloads into appropriate folders
  - Includes resolution and date in filenames
  - Creates separate folders for different media types

- **Subtitle Support**:
  - Downloads subtitles in multiple languages
  - **NEW**: Improved support for auto-generated captions
  - **NEW**: Better subtitle format detection and conversion
  - **NEW**: Fixed path handling for subtitle files
  - Converts subtitles to SRT format
  - Checks subtitle availability before downloading

- **Playlist Support**:
  - Option to download entire playlists
  - Maintains consistent quality settings across playlist

- **Robust Error Handling**:
  - **NEW**: Improved error recovery with multiple fallback methods
  - **NEW**: Specific handling for different error types
  - Automatically retries failed downloads
  - Handles format unavailability gracefully
  - Provides detailed error messages

## Requirements

- Windows with PowerShell
- [yt-dlp](https://github.com/yt-dlp/yt-dlp) (included or in PATH)
- [ffmpeg](https://ffmpeg.org/download.html) (included in ffmpeg folder)

## Installation

1. Download the latest release
2. Extract all files to a folder of your choice
3. Make sure ffmpeg is in the `ffmpeg\bin\` subfolder
4. Make sure yt-dlp.exe is either in the same folder or in your system PATH

## Usage

1. Run the script by right-clicking `YT-MediaFetcher-v7.ps1` (for GPU acceleration) or `YT-MediaFetcher-v2.ps1` and selecting "Run with PowerShell" or by opening PowerShell and running:
   ```
   .\YT-MediaFetcher-v7.ps1  # For GPU-accelerated version
   ```
   or
   ```
   .\YT-MediaFetcher-v2.ps1  # For standard version
   ```

2. Follow the on-screen prompts:
   - Enter a YouTube URL (video or playlist)
   - Choose whether to download the entire playlist
   - Select download type (video, audio, or subtitles)
   - Choose quality options

3. The script will:
   - Check available formats and their sizes
   - Download the selected content
   - Save it to the appropriate subfolder in the "Downloads" directory

## How It Works

### Services and Tools Used

The script utilizes two main external tools:

1. **yt-dlp**:
   - Handles all YouTube API interactions and video downloading
   - Manages format selection and extraction
   - Handles playlist processing
   - Downloads subtitles
   - Provides progress reporting
   - Manages retry mechanisms for failed downloads

2. **ffmpeg**:
   - Processes and converts media files
   - Provides hardware acceleration via GPU
   - Extracts and converts audio to MP3
   - Converts subtitles to SRT format
   - Merges video and audio streams
   - Handles all media encoding/decoding

All downloading and processing happens locally on your machine using these two tools, with the script coordinating between them and providing a user-friendly interface.

### Format Detection

The script uses yt-dlp's JSON output to analyze all available formats for a video:

1. It retrieves detailed information about all available formats
2. Identifies which resolutions are available and their estimated sizes
3. Checks which formats include both video and audio
4. Displays a comprehensive list of available options

### Download Process

When downloading videos, the script:

1. **Format Analysis**:
   - Analyzes all available formats for the video
   - Identifies which formats have both video and audio
   - Selects the best format for your chosen resolution

2. **Parallel Fragment Downloading**:
   - Splits the download into multiple fragments (default: 32)
   - Downloads these fragments simultaneously
   - Shows progress for each fragment (e.g., [frag 4/16])
   - Automatically retries failed fragments

3. **Format Handling**:
   - For "Video with Audio":
     * If a combined format exists, downloads it directly
     * Otherwise, downloads video and audio streams separately
     * Uses ffmpeg to merge them into a single MP4 file
   - For "Video Only" or "Audio Only":
     * Downloads only the requested stream type
     * Optimizes for the highest quality available

4. **Post-Processing**:
   - Merges all fragments into a complete file
   - Converts audio to MP3 format if requested
   - Extracts and converts subtitles if available
   - Cleans up temporary files

5. **Organization**:
   - Sorts downloads into appropriate folders by media type
   - Names files with resolution and date information
   - Creates a detailed log file of all operations

### Configuration

The script creates a `ytdl_config.json` file that stores:
- Default resolution preferences
- Default audio quality
- Number of concurrent download fragments
- Subtitle language preferences

## Troubleshooting

- **Script gets stuck**: Press Ctrl+C to cancel and try again
- **Format not available**: The script will automatically try the next best available format
- **Videos not playing smoothly on mobile**: Fixed with new mobile-optimized encoding settings that ensure smooth playback on all devices
- **Subtitles not downloading**: Fixed with improved automatic caption detection and multiple download methods
- **Slow merging process**: The script now uses optimized settings for merging, but for very large files, it may still take time
- **Post-processor warnings**: These have been fixed with proper parameter formatting
- **Audio conversion is slow**: Try using the script on videos that have MP3 format directly available, which will skip conversion entirely
- **HTTP Error 416**: The script now automatically retries with single-fragment download when this error occurs
- **M4A to MP3 conversion issues**: Fixed with improved file extension handling and direct ffmpeg conversion fallback
- **DASH m4a warnings**: Suppressed warnings and improved format selection to avoid DASH containers when possible
- **Network timeouts**: Implemented adaptive network handling with automatic retry using more conservative settings
- **Connection issues**: Added specialized error recovery for various network problems with optimized parameters
- **Subtitle download hangs**: Fixed with timeout protection and multiple fallback methods
- **Subtitle detection issues**: Improved with better automatic caption detection and support for auto-generated captions
- **YouTube Shorts support**: Added special format handling for YouTube Shorts
- **Null resolution errors**: Fixed with fallback resolution for special format videos

## Advanced Usage

- **Custom Output Templates**: Edit the script to customize filename formats
- **Additional Parameters**: Modify the yt-dlp command parameters for special needs
- **Batch Processing**: Create a text file with URLs and process them in sequence

## Performance Optimization

### Latest Optimizations (2024)

The script has been significantly optimized to provide faster downloads and processing while maintaining high quality:

#### 1. Mobile-Optimized Video Encoding
- **NEW**: Uses baseline profile and level 4.0 for maximum device compatibility
- **NEW**: Optimized bitrate settings for smooth playback on mobile devices
- **NEW**: Proper keyframe settings for better seeking and playback performance
- **NEW**: Uses yuv420p pixel format for universal compatibility
- **NEW**: GPU-specific optimizations for mobile-friendly encoding

#### 2. Balanced Quality and Speed Settings
- Uses the `medium` preset for encoding, balancing quality and speed
- Implements multi-threading with 8 threads for faster processing
- Optimizes container settings with `movflags faststart+frag_keyframe+empty_moov`
- Increases queue size with `max_muxing_queue_size 4096` for smoother merging

#### 2. Direct MP3 Download
- Automatically detects when MP3 format is directly available from YouTube
- Skips the conversion step entirely when possible, dramatically reducing processing time
- Falls back to optimized conversion when direct MP3 is not available

#### 3. Optimized Audio Conversion
- Uses `libmp3lame` encoder with variable bitrate for faster audio processing
- Implements optimized audio resampling parameters
- Doubles concurrent fragments specifically for audio downloads (up to 64)
- Uses larger buffer size (32MB) for audio downloads

#### 4. Improved Merging Process
- Optimizes the video and audio merging process with specialized parameters
- Uses proper post-processor arguments to avoid warnings
- Implements intelligent fallback mechanisms for different error scenarios

#### 5. GPU-Specific Optimizations
- **NVIDIA GPUs**: 
  - Uses preset p2 for mobile-optimized encoding
  - Implements baseline profile and level 4.0 for maximum compatibility
  - Optimized bitrate and buffer settings for smooth mobile playback
- **AMD GPUs**: 
  - Implements specialized audio processing parameters
  - Uses balanced quality settings for mobile compatibility
- **Intel GPUs**: 
  - Optimizes QuickSync settings for both video and audio
  - Configures mobile-friendly encoding parameters

### GPU Acceleration

Version 7 of the script includes comprehensive GPU acceleration support to offload encoding/decoding tasks from the CPU to the GPU.

#### How It Works:
- Automatically detects available hardware acceleration methods on your system
- Prioritizes acceleration methods in this order: CUDA, NVENC, AMF, QSV, D3D11VA, DXVA2, VAAPI
- Applies optimized encoding parameters specific to your GPU type
- Uses GPU for both video and audio processing

#### Supported GPU Types:
- **NVIDIA GPUs**: Uses CUDA and NVENC with optimized parameters
- **AMD GPUs**: Uses AMF (Advanced Media Framework)
- **Intel GPUs**: Uses QuickSync Video (QSV)
- **Generic**: Falls back to DirectX acceleration (D3D11VA, DXVA2) if available

#### Configuration:
GPU acceleration can be enabled or disabled in the `ytdl_config.json` file:
```json
{
  "EnableHWAccel": true,
  "PreferredHWAccel": "auto"
}
```

- `EnableHWAccel`: Set to `true` to enable GPU acceleration, `false` to disable
- `PreferredHWAccel`: Set to `"auto"` for automatic detection, or specify a method like `"cuda"`, `"nvenc"`, etc.

#### Benefits:
- Significantly reduces CPU usage during downloads
- Faster video and audio processing
- Improved overall download speeds, especially for high-resolution videos
- Allows your computer to remain responsive during downloads

### Improved Command Structure

The script now uses a modular command generation system that ensures proper parameter formatting and eliminates warnings:

#### Key Improvements:
- Uses the correct `--postprocessor-args` parameter instead of the shorthand `--ppa`
- Explicitly specifies which post-processor should receive arguments
- Provides consistent parameter formatting across all download types
- Implements intelligent error handling with appropriate fallback mechanisms

### Concurrent Fragments

The script uses yt-dlp's parallel download capability to speed up downloads by splitting videos into multiple fragments and downloading them simultaneously.

#### How It Works:
- YouTube videos are split into small chunks or "fragments"
- The script downloads multiple fragments in parallel
- After downloading, fragments are automatically joined into a complete file
- For "Video with Audio" downloads, it often downloads video and audio separately, then merges them
- **NEW**: Audio downloads now use up to 64 concurrent fragments for even faster processing

#### Adjusting Concurrent Fragments:

The default setting is 32 concurrent fragments for video and 64 for audio, which provides excellent performance on most systems. You can adjust these values in the `ytdl_config.json` file:

```json
{
  "DefaultResolution": "1080",
  "DefaultAudioQuality": "192",
  "MaxConcurrentFragments": 32,
  "MaxAudioFragments": 64,
  "SubtitleLanguage": "en",
  "BufferSize": "16M",
  "AudioBufferSize": "32M"
}
```

**Increasing the value** (e.g., to 48 or 64 for video, 96 or 128 for audio):
- **Benefits**: Potentially faster downloads on high-speed connections
- **Drawbacks**: Higher CPU/memory usage, possible network instability

**Decreasing the value** (e.g., to 16 or 8):
- **Benefits**: Lower system resource usage, more stable on slower connections
- **Drawbacks**: Slower download speeds

#### Recommended Settings:

| Internet Speed | System Specs | Video Fragments | Audio Fragments |
|----------------|--------------|-----------------|-----------------|
| 100+ Mbps      | Modern       | 32-64           | 64-128          |
| 50-100 Mbps    | Average      | 16-32           | 32-64           |
| 20-50 Mbps     | Average      | 8-16            | 16-32           |
| <20 Mbps       | Any          | 4-8             | 8-16            |

#### Notes:
- There's a point of diminishing returns - more fragments won't always mean faster downloads
- If you experience errors or connection issues, try reducing the number of fragments
- The improvement is most noticeable for large videos (1080p or higher)
- Audio downloads benefit significantly from higher fragment counts due to smaller file sizes

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- [yt-dlp](https://github.com/yt-dlp/yt-dlp) for the amazing YouTube download engine
- [ffmpeg](https://ffmpeg.org/) for media processing capabilities