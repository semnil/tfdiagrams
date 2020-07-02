# -*- coding: utf-8 -*-
import argparse
import sys
from tfdiagrams import generate


def main():
    parser = argparse.ArgumentParser()

    # graph name
    parser.add_argument('-n', default='tfdiagrams')
    # output format
    parser.add_argument('-T', default='png')
    # output file name
    parser.add_argument('-o', default='tfdiagrams.png')
    # exclude keywords separated by commas
    parser.add_argument('-e', default='')
    # input file name
    parser.add_argument('arg1', nargs='?', default='')

    args = parser.parse_args()

    if args.arg1 != '':
        # input string from file
        with open(args.arg1) as f:
            dot = f.read()
    else:
        # input string from stdin
        dot = ''
        for line in sys.stdin:
            dot += line

    # patch the file output by terraform
    dot = dot.replace('["', '[\\"').replace('"] ', '\\"] ')

    generate.Diagram(dot, args.n, args.T, args.o, args.e)
    return 0
