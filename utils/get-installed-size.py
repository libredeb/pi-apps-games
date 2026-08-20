import subprocess
import sys
import tarfile
from io import BytesIO

def get_deb_unpacked_size(deb_path):
    try:
        # Try extracting 'data.tar.xz' directly into memory
        process = subprocess.Popen(
            ["ar", "p", deb_path, "data.tar.xz"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        stdout, stderr = process.communicate()

        # If xz format is not found, try gzip (common in older or alternative debs)
        if process.returncode != 0:
            process = subprocess.Popen(
                ["ar", "p", deb_path, "data.tar.gz"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )
            stdout, stderr = process.communicate()

        if process.returncode != 0:
            print("Error: Could not extract data from the .deb package. Verify it is a valid package.", file=sys.stderr)
            return None

        # Open the byte stream as a tar file and sum the size of all files
        bytes_io = BytesIO(stdout)
        total_bytes = 0
        
        with tarfile.open(fileobj=bytes_io, mode="r:*") as tar:
            for member in tar.getmembers():
                if member.isfile():
                    total_bytes += member.size
                    
        return total_bytes

    except FileNotFoundError:
        print("Error: The 'ar' command is missing. Please install the 'binutils' package.", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Unexpected error: {e}", file=sys.stderr)
        return None

def to_human_readable(size_bytes):
    # Converts bytes into a human-readable format (KB, MB, GB, etc.)
    for unit in ['Bytes', 'KB', 'MB', 'GB', 'TB']:
        if size_bytes < 1024.0:
            return f"{size_bytes:.2f} {unit}"
        size_bytes /= 1024.0
    return f"{size_bytes:.2f} PB"

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 script.py <path_to_package.deb>")
        sys.exit(1)
        
    file_path = sys.argv[1]
    total_bytes = get_deb_unpacked_size(file_path)
    
    if total_bytes is not None:
        print(f"Estimated unpacked size: {to_human_readable(total_bytes)}")
