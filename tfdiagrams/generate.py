# -*- coding: utf-8 -*-
from tfdiagrams import resources

from diagrams import Diagram
from diagrams import setdiagram
from pathlib import Path

import diagrams.aws.analytics
import diagrams.aws.ar
import diagrams.aws.blockchain
import diagrams.aws.business
import diagrams.aws.compute
import diagrams.aws.cost
import diagrams.aws.database
import diagrams.aws.devtools
import diagrams.aws.enablement
import diagrams.aws.enduser
import diagrams.aws.engagement
import diagrams.aws.game
import diagrams.aws.general
import diagrams.aws.integration
import diagrams.aws.iot
import diagrams.aws.management
import diagrams.aws.media
import diagrams.aws.migration
import diagrams.aws.ml
import diagrams.aws.mobile
import diagrams.aws.network
import diagrams.aws.quantum
import diagrams.aws.robotics
import diagrams.aws.satellite
import diagrams.aws.security
import diagrams.aws.storage
import os
import pydot
import re

EXCLUDE_NODES = [
    # global
    'output',
    'var',
]


class BlankGraph(Diagram):
    def __exit__(self, exc_type, exc_value, traceback):
        # self.render()
        setdiagram(None)


class Diagram:
    def set_node_styles(self, node):
        node.set_fixedsize('true')
        node.set_fontcolor('#2D3436')
        node.set_height(2.2)
        node.set_width(1.4)
        node.set_style('rounded')
        node.set_shape('none')

    def replace_node(self, node):
        node_name = node.get_name()
        if ' ' in node_name:
            label_items = node_name.replace('"', '').split(' ')[0].split('.')
        else:
            label_items = node_name.replace('"', '').split('.')
        resource_instance = None
        for i in label_items:
            if i in resources.RESOURCES_MAP:
                if resources.RESOURCES_MAP[i]:
                    resource_instance = eval('diagrams.' + resources.RESOURCES_MAP[i] + '()')
                    break

        if resource_instance:
            node.set_image(resource_instance._load_icon())
            self.set_node_styles(node)
        else:
            node.set_height(0.0)

        # label break
        height = node.get_height()
        label = ''
        line_break = False
        for i in label_items:
            if not len(label) == 0:
                label += '.'
            label += i
            if i.startswith('aws_'):
                label += '\\n'
                height += 0.4
            elif line_break:
                label += '\\n'
                height += 0.4
                line_break = False
            if 'module' in i:
                line_break = True
        node.set_label(label)
        node.set_height(height)

        # check exclude keywords
        items = []
        for i in self.excludes:
            for j in label_items:
                if i == j \
                        or ('*' in i and re.search(i.replace('*', '.*'), j)):
                    # Allow exact match or wildcard
                    items += i
        if len(items) == 0:
            node.set_name(node_name)
            return node

        return None


    def add_node(self, graph, node):
        node_name = node.get_name()
        if node_name != 'node' and node_name != '"\\n"':
            new_node = self.replace_node(node)
            if new_node:
                graph.add_node(new_node)


    def __init__(self, dot: str = "", name: str = 'tfdiagrams', outformat: str = 'png', filename: str = 'tfdiagrams.png',
                 excludes: str = ''):
        self.dot = dot
        self.name = name
        self.outformat = outformat
        self.filename = filename
        self.excludes = EXCLUDE_NODES + excludes.split(',')

        with BlankGraph():
            # load object from dot file
            (graph,) = pydot.graph_from_dot_data(self.dot)

            # graph settings
            new_graph = pydot.Dot(graph_type='digraph')
            new_graph.set_graph_defaults(fontcolor='#2D3436', fontname='sans-serif', fontsize=15,
                                         label='"' + self.name + '"')
            #                              nodesep=0.60, pad=2.0, rankdir='LR', ranksep=2.30, splines='ortho')
            new_graph.set_node_defaults(fontcolor='#2D3436', fontname='sans-serif', fontsize=13,
                        imagescale='true', labelloc='b', shape='box')

            new_graph.set_rankdir("RL")

            basedir = Path(os.path.abspath(os.path.dirname(__file__)))
            self.blank_image = os.path.join(basedir.parent, 'tfdiagrams/resources/blank.png')

            # add nodes
            for node in graph.get_node_list():
                if node.get_name() != '"\\n"':
                    self.add_node(new_graph, node)

            # add subgraphs
            for subgraph in graph.get_subgraph_list():
                h = pydot.Subgraph(subgraph.get_name())
                h.set_label(subgraph.get_label())
                for node in subgraph.get_node_list():
                    if node.get_name() != '"\\n"':
                        self.add_node(h, node)
                new_graph.add_subgraph(h)

            # add edges
            for edge in graph.get_edge_list():
                source_name = edge.get_source()
                if ' ' in source_name:
                    source_items = source_name.replace('"', '').split(' ')[0].split('.')
                else:
                    source_items = source_name.replace('"', '').split('.')
                destination_name = edge.get_destination()
                if ' ' in destination_name:
                    destination_items = destination_name.replace('"', '').split(' ')[0].split('.')
                else:
                    destination_items = destination_name.replace('"', '').split('.')

                # check exclude keywords
                items = []
                for i in self.excludes:
                    for j in source_items + destination_items:
                        if i == j \
                                or ('*' in i and re.search(i.replace('*', '.*'), j)):
                            # Allow exact match or wildcard
                            items += i
                if len(items) == 0:
                    new_edge = pydot.Edge(source_name, destination_name)
                    new_graph.add_edge(new_edge)

            # output graph file
            new_graph.write(self.filename, format=self.outformat, prog='dot')
