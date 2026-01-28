import argparse

from jaclang.vendor import jaccomplete

p = argparse.ArgumentParser()
sub = p.add_subparsers()
sub.add_parser("foo")
jaccomplete.autocomplete(p)
print("Autocomplete returned")
