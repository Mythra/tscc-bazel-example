"""Bazel Rules for interacting with typescript config rules
"""

def _join(*elements):
  return '/'.join([f for f in elements if f])

def _relative_path(tsconfig, dest):
  relative_to = tsconfig.dirname
  if dest.is_source:
    # Calculate a relative path from the directory where we're writing the tsconfig
    # back to the sources root
    workspace_root = '/'.join(['..'] * len(relative_to.split('/')))
    return _join(workspace_root, dest.path)

  # Bazel guarantees that srcs are beneath the package directory, and we disallow
  # tsconfig.json being generated with a "/" in the name.
  # So we can calculate a relative path from e.g.
  # bazel-out/darwin-fastbuild/bin/packages/typescript/test/ts_project/generated_tsconfig/gen_src
  # to <generated file packages/typescript/test/ts_project/generated_tsconfig/gen_src/subdir/a.ts>
  result = dest.path[len(relative_to) + 1:]
  if not result.startswith('.'):
      result = './' + result
  return result

def _write_typescript_config_rule(ctx):
  content = '\n'.join(ctx.attr.content)
  if ctx.attr.files:
    content = content.replace(
      '"__files__"',
      str([_relative_path(ctx.outputs.out, f) for f in ctx.files.files]),
    )
  ctx.actions.write(
    output = ctx.outputs.out,
    content = content,
  )
  return [DefaultInfo(files = depset([ctx.outputs.out]))]

write_typescript_config_rule = rule(
  implementation = _write_typescript_config_rule,
  attrs = {
    'content': attr.string_list(),
    'files': attr.label_list(allow_files = True),
    'out': attr.output(),
  },
)

def write_typescript_config(name, config, files, out):
  """Wrapper around bazel_skylib's write_file which understands tsconfig paths

  Args:
      name: name of the resulting write_file rule
      config: tsconfig dictionary
      files: list of input .ts files to put in the files[] array
      out: the file to write
  """
  if out.find('/') >= 0:
    fail('tsconfig should be generated in the package directory, to make relative pathing simple')

  amended_config = struct(
    files = '__files__',
    **config
  )
  write_typescript_config_rule(
    name = name,
    files = files,
    content = [json.encode(amended_config)],
    out = out,
  )
