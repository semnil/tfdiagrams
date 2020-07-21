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
    'count-boundary',
    'data',
    'output',
    'provider',
    'var',
]


class BlankGraph(Diagram):
    def __exit__(self, exc_type, exc_value, traceback):
        # self.render()
        setdiagram(None)


class Diagram:
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
            new_graph.set_graph_defaults(fontcolor='#2D3436', fontname='Sans-serif', fontsize=15,
                                         label='"' + self.name + '"',
                                         nodesep=0.60, pad=2.0, rankdir='LR', ranksep=2.30, splines='ortho')
            new_graph.set_node_defaults(fixedsize='true', fontcolor='#2D3436', fontname='Sans-serif', fontsize=13,
                                        height=1.4,
                                        imagescale='true', labelloc='b', shape='box', style='rounded', width=1.4)

            # create subgraph
            root = graph.get_subgraph('"root"')[0]
            new_root = pydot.Subgraph()
            new_graph.add_subgraph(new_root)

            basedir = Path(os.path.abspath(os.path.dirname(__file__)))
            blank_image = os.path.join(basedir.parent, 'tfdiagrams/resources/blank.png')

            # add nodes
            for node in root.get_node_list():
                node_name = node.get_name().replace('[' + 'root' + '] ', '')
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
                else:
                    node.set_image(blank_image)
                node.set_shape('none')

                # label break
                height = 2.0
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
                    new_root.add_node(node)

            # add edges
            for edge in root.get_edge_list():
                source_name = edge.get_source().replace('[' + 'root' + '] ', '')
                if ' ' in source_name:
                    source_items = source_name.replace('"', '').split(' ')[0].split('.')
                else:
                    source_items = source_name.replace('"', '').split('.')
                destination_name = edge.get_destination().replace('[' + 'root' + '] ', '')
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
                    new_root.add_edge(new_edge)

            # output graph file
            new_graph.write(self.filename, format=self.outformat, prog='dot')
