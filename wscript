import json
import os
import re

from waflib.Configure import conf

top = '.'
out = 'build'

def developer_mode():
    return "PEBBLE_DEVELOPER" in os.environ

def options(ctx):
    ctx.load('pebble_sdk')

def configure(ctx):
    ctx.load('pebble_sdk')

def build(ctx):
    ctx.load('pebble_sdk')

    ctx.pbl_program(source=ctx.path.ant_glob('src/**/*.c'),
                    cflags=['-Wno-address',
                            '-Wno-type-limits',
                            '-Wno-missing-field-initializers'],
                    target='pebble-app.elf')

    js_target = ctx.concat_javascript(js_path='src/js')

    ctx.pbl_bundle(elf='pebble-app.elf',
                   js=js_target)

@conf
def concat_javascript(self, *k, **kw):
    js_path = kw['js_path']
    js_nodes = (self.path.ant_glob(js_path + '/**/*.js') +
                self.path.ant_glob(js_path + '/**/*.json') +
                self.path.ant_glob(js_path + '/**/*.coffee'))

    if not js_nodes:
        return []

    def concat_javascript_task(task):
        LOADER_PATH = "loader.js"
        LOADER_TEMPLATE = ("__loader.define({relpath}, {lineno}, " +
                           "function(exports, module, require) {{\n{body}\n}});")
        JSON_TEMPLATE = "module.exports = {body};"
        APPINFO_PATH = "appinfo.json"

        def loader_translate(source, lineno):
            return LOADER_TEMPLATE.format(
                    relpath=json.dumps(source['relpath']),
                    lineno=lineno,
                    body=source['body'])

        def coffeescript_compile(relpath, body):
            try:
                import coffeescript
            except ImportError:
                self.fatal("""
    Coffeescript file '%s' found but coffeescript module isn't installed.
    You may try `pip install coffeescript` or `easy_install coffeescript`.
                """ % (relpath))
            body = coffeescript.compile(body)
            # change ".coffee" or ".js.coffee" extensions to ".js"
            relpath = re.sub('(\.js)?\.coffee$', '.js', relpath)
            return relpath, body

        sources = []
        if developer_mode():
            sources.append("var PEBBLE_DEVELOPER = true;")
        for node in task.inputs:
            relpath = os.path.relpath(node.abspath(), js_path)
            with open(node.abspath(), 'r') as f:
                body = f.read()
                if relpath.endswith('.json'):
                    body = JSON_TEMPLATE.format(body=body)
                elif relpath.endswith('.coffee'):
                    relpath, body = coffeescript_compile(relpath, body)

                if relpath == LOADER_PATH:
                    sources.insert(0, body)
                elif relpath.startswith('vendor/'):
                    sources.append(body)
                else:
                    sources.append({ 'relpath': relpath, 'body': body })

        with open(APPINFO_PATH, 'r') as f:
            body = JSON_TEMPLATE.format(body=f.read())
            sources.append({ 'relpath': APPINFO_PATH, 'body': body })

        sources.append('__loader.require("main");')

        with open(task.outputs[0].abspath(), 'w') as f:
            lineno = 1
            for source in sources:
                if type(source) is dict:
                    out = loader_translate(source, lineno)
                else:
                    out = source
                f.write(out + '\n')
                lineno += out.count('\n') + 1

    js_target = self.path.make_node('build/src/js/pebble-js-app.js')

    self(rule=concat_javascript_task,
        source=js_nodes,
        target=js_target)

    return js_target

# vim:filetype=python
