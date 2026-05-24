import time
import subprocess
import os

def benchmark():
    rex_code = "output 1000000 + 0"
    with open("bench.rex", "w") as f:
        f.write(rex_code)

    # Compile Rex
    subprocess.run(["./rexc", "bench.rex"])

    start = time.time()
    subprocess.run(["./output"], capture_output=True)
    rex_time = time.time() - start

    print(f"Rex execution time: {rex_time:.6f}s")
    print(f"Rex binary size: {os.path.getsize('output')} bytes")

    # Python
    start = time.time()
    subprocess.run(["python3", "-c", "print(1000000 + 0)"], capture_output=True)
    py_time = time.time() - start
    print(f"Python execution time: {py_time:.6f}s")

if __name__ == "__main__":
    benchmark()
