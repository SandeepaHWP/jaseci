import argparse
import os
import sys

from jaclang.vendor import jaccomplete

# Simulate completion environment
os.environ["_ARGCOMPLETE"] = "1"
os.environ["_ARGCOMPLETE_SHELL"] = "bash"
os.environ["COMP_LINE"] = "prog foo"
os.environ["COMP_POINT"] = "8"
os.environ["COMP_WORDBREAKS"] = " \t\n\"'><=;|&(:"
os.environ["_ARGCOMPLETE_STDOUT_FILENAME"] = "completion_output.txt"
# os.environ['_ARC_DEBUG'] = '1' # Enable if needed


def test():
    p = argparse.ArgumentParser()
    p.add_argument("--bar")
    p.add_argument("--baz")
    sub = p.add_subparsers()
    sub.add_parser("food")
    sub.add_parser("foot")

    print("Running completion test...")
    try:
        # This should exit with code 0 and print completions if successful
        jaccomplete.autocomplete(p, exit_method=sys.exit)
    except SystemExit as e:
        print(f"Caught expected exit: {e}")
    except Exception as e:
        print(f"Caught unexpected exception: {e}")

    if os.path.exists("completion_output.txt"):
        with open("completion_output.txt") as f:
            print("Completion Output:", f.read())
    else:
        print("No completion output file generated.")


if __name__ == "__main__":
    test()
