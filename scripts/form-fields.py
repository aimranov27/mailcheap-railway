"""Prints the hidden React server-action fields of an HTML form, one name=value per line.

Usage: python3 -I form-fields.py page.html <field-name>
Picks the first form that has an input named <field-name>. The smoke test posts these
fields with curl, which is how a browser submits the form before JavaScript loads.
"""

import html.parser
import sys


class Forms(html.parser.HTMLParser):
    def __init__(self):
        super().__init__()
        self.forms = []
        self.current = None

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "form":
            self.current = []
            self.forms.append(self.current)
        elif tag == "input" and self.current is not None and attrs.get("name"):
            self.current.append((attrs["name"], attrs.get("value") or ""))

    def handle_endtag(self, tag):
        if tag == "form":
            self.current = None


def main():
    page, field = sys.argv[1], sys.argv[2]
    parser = Forms()
    with open(page, encoding="utf-8") as handle:
        parser.feed(handle.read())
    for form in parser.forms:
        if any(name == field for name, _ in form):
            for name, value in form:
                if name.startswith("$ACTION"):
                    print(f"{name}={value}")
            return
    sys.exit(f"no form with a field named {field} in {page}")


main()
