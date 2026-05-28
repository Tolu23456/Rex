import subprocess
import os
import signal
import time

def main():
    if os.path.exists('output'):
        os.remove('output')

    # Compile the compiler with debug prints if possible, but here we just run it
    proc = subprocess.Popen(['./rexc', 'tests/float.rex'])

    start_time = time.time()
    while proc.poll() is None:
        if time.time() - start_time > 2:
            print("Compiler timed out (2s).")
            proc.terminate()
            return
        time.sleep(0.1)

    print(f"Compiler finished with code {proc.returncode}")
    if os.path.exists('output'):
        print("Generated 'output' binary.")

        print("Running 'output'...")
        try:
            out = subprocess.check_output(['./output'], timeout=2, stderr=subprocess.STDOUT)
            print(f"Output: {out.decode()}")
        except subprocess.TimeoutExpired:
            print("Generated binary 'output' timed out!")
        except Exception as e:
            print(f"Error running 'output': {e}")

if __name__ == "__main__":
    main()
