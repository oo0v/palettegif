This batch script uses FFmpeg and FFProbe to convert video files to GIF format based on either a specified height in pixels or a target file size in MB.
You can specify the frame rate, height, and desired file size.
If the resulting GIF would be smaller than the target size using the specified height, it will be output as is.
If the output would exceed the target size, the script performs a binary search (up to 10 iterations) to adjust the height until the file size is within 1MB of the target.
