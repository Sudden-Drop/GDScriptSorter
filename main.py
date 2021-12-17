# import typing
from __future__ import annotations
from enum import Enum
from collections import namedtuple
from functools import cmp_to_key
from abc import ABC, abstractmethod


TaggedLine = namedtuple("TaggedLine", "line priorities")


class TreeWorker(ABC):
    @abstractmethod
    def accept(self, tree: Node):
        return tree


class TreeSorter(TreeWorker):
    def accept(self, tree: Node) -> Node:
        for child in tree.children:
            self.accept(child)
        tree.children.sort(key=cmp_to_key(lambda a, b: 0 if Node.is_irrelevant(a.tag) or Node.is_irrelevant(b.tag) else a.tag.value - b.tag.value))
        return tree


class TreeUnspacer(TreeWorker):
    # removing blank lines helps with the sorting
    def accept(self, tree: Node) -> Node:
        tree.children = [n for n in tree.children if n.tag != Tag.BLANK_LINE]
        for child in tree.children:
            self.accept(child)
        return tree


class TreeSpacer(TreeWorker):
    # doesn't work properly, but doesn't matter.
    # Running `gdformat script.gd` fixes spacing anyway.
    def accept(self, tree: Node) -> Node:
        tree.children = [c for c in tree.children if c.tag != Tag.BLANK_LINE]
        for c in tree.children:
            self.accept(c)

        for i in [i for i in range(len(tree.children)) if tree.children[i].children]:
            tree.children.insert(i, Node(Tag.BLANK_LINE, 1, "\n"))

        return tree


class TreePrinter(TreeWorker):
    def accept(self, tree: Node) -> str:
        s = tree.content
        for child in tree.children:
            s += self.accept(child)
        return s


class Node:
    @staticmethod
    def is_irrelevant(tag) -> bool:
        return tag in [Tag.IGNORE, Tag.BLANK_LINE]

    @staticmethod
    def node_comp(n1, n2) -> int:
        return 0 if Node.is_irrelevant(n1.tag) or Node.is_irrelevant(n2.tag) else n1.tag.value - n2.tag.value

    def __init__(self, tag, indent, content):
        self.tag = tag
        self.indent = indent
        self.parent = None
        self.children = []
        self.content = content

    def get_semantic_children(self):
        # only children that are not of type IGNORE
        return [child for child in self.children if not Node.is_irrelevant(child.tag)]

    def add_child(self, node: Node):
        self.children.append(node)
        node.parent = self

    def sort(self):
        for child in self.children:
            child.sort()
        self.children.sort(key=cmp_to_key(Node.node_comp))

    def __str__(self):
        return self.to_string("")

    def to_string(self, indent):
        s = "%s%s(\n" % (indent, self.tag)
        for c in self.children:
            s += c.to_string(indent + "  ")
            s += "\n"
        s += indent + ")"
        return s

class Tag(Enum):
    # https://docs.godotengine.org/en/stable/getting_started/scripting/gdscript/gdscript_styleguide.html#code-order
    ROOT = -1
    TOOL = 10
    CLASS_NAME = 20
    INHERITANCE = 30
    DOCSTRING = 40
    SIGNAL = 50
    ENUM = 60
    CONST = 70
    EXPORT_VAR = 80
    VAR = 90  # public and private
    ONREADY = 100
    FN_INIT = 110
    FN_READY = 120
    FN_BUILTIN = 130
    INNER_CLASS = 140
    STATIC_METHOD = 150
    METHOD = 160
    IGNORE = 1000
    BLANK_LINE = 2000

    def __lt__(self, other):
        return self.value < other.value


def indent_length(ident: str) -> int:
    return len(ident)  # hook in here for tabs vs spaces


# FIXME: make work for different spacing types
class TreeGenerator:
    def __init__(self):
        self._current_block = None

    def classify(self, line: str, line_number: int) -> Tag:
        tag = Tag.IGNORE
        if line.strip() == "":
            tag = Tag.BLANK_LINE
        elif line.startswith("tool"):
            tag = Tag.TOOL
        elif line.startswith("class_name"):
            tag = Tag.CLASS_NAME
        elif line.startswith("extends"):
            tag = Tag.INHERITANCE
        elif line.startswith("#"):
            children = self._current_block.get_semantic_children()
            # if either we have only encountered whitespace so far, or the last node was a docstring itself
            # (or another node that comes before that) then the line is a docstring too.
            # Else, it's just a regular comment → IGNORE
            tag = Tag.DOCSTRING if self._current_block.tag.value <= Tag.DOCSTRING.value and (len(children) == 0 or children[-1].tag.value <= Tag.DOCSTRING.value) else Tag.IGNORE
        elif line.startswith("const"):
            tag = Tag.CONST
        elif line.startswith("signal"):  # FIXME: check for looong signals
            tag = Tag.SIGNAL
        elif line.startswith("var"):
            tag = Tag.VAR
        elif line.startswith("export"):
            tag = Tag.EXPORT_VAR
        elif line.startswith("onready"):
            tag = Tag.ONREADY
        elif line.startswith("static func "):
            tag = Tag.STATIC_METHOD
        elif line.startswith("func _init"):
            tag = Tag.FN_INIT
        elif line.startswith("func _ready"):
            tag = Tag.FN_READY
        elif line.startswith("func _"):
            tag = Tag.FN_BUILTIN
        elif line.startswith("func "):
            tag = Tag.METHOD
        elif line.startswith("enum "):
            tag = Tag.ENUM
        elif line.startswith("class"):
            tag = Tag.INNER_CLASS

        return tag

    def treeify(self, lines):
        self._current_block = Node(Tag.ROOT, -1, "")

        for i in range(len(lines)):
            line = lines[i]
            stripped = line.lstrip()
            tag = self.classify(stripped, i + 1)
            indent = indent_length(line) - indent_length(stripped)
            if not line.endswith("\n"):
                # fix last line of file.
                # If that line is sorted to some other place, the
                # newline would be missing
                line += "\n"

            new_block = Node(tag, indent, line)
            if stripped:  # empty lines don't affect indent
                if indent == self._current_block.indent + 1:  # append to current parent block
                    self._current_block.add_child(new_block)
                elif indent == self._current_block.indent + 2:  # last block was actually a new parent block → fix up
                    self._current_block = self._current_block.children[-1]
                    self._current_block.add_child(new_block)
                    """
                    elif indent < self._current_block.indent:  # dedent → pop block(s)
                        while indent < self._current_block.indent:
                            self._current_block = self._current_block.parent
                        self._current_block.add_child(new_block)
                    """
                else:  # same level → new block
                    while indent < self._current_block.indent:
                        self._current_block = self._current_block.parent
                    assert indent == self._current_block.indent
                    self._current_block.parent.add_child(new_block)
                    self._current_block = new_block
            else:  # whitespace
                self._current_block.add_child(new_block)

        while self._current_block.parent is not None:
            self._current_block = self._current_block.parent

        return self._current_block


def main():
    tg = TreeGenerator()
    with open("./test/FogOfWar3D.gd", "r") as fh:
        lines = fh.readlines()
        tree = tg.treeify(lines)
        for worker in [TreeUnspacer(), TreeSorter(), TreePrinter()]:
            tree = worker.accept(tree)

        print(tree)


if __name__ == "__main__":
    main()
