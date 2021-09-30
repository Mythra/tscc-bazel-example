"""Bazel Rules for interacting with typescript config rules
"""

def _write_tscc_config_rule(ctx):
  content = '\n'.join(ctx.attr.content)
  ctx.actions.write(
    output = ctx.outputs.out,
    content = content,
  )
  return [DefaultInfo(files = depset([ctx.outputs.out]))]

write_tscc_config_rule = rule(
  implementation = _write_tscc_config_rule,
  attrs = {
    'content': attr.string_list(),
    'out': attr.output(),
  },
)

def write_tscc_config(name, config, out):
  """Write a tscc config file

  Args:
      name: name of the resulting write_file rule
      config: tsconfig dictionary
      out: the file to write
  """
  if out.find('/') >= 0:
    fail('tscc_config should be generated in the package directory, to make relative pathing simple')

  write_tscc_config_rule(
    name = name,
    content = [json.encode(config)],
    out = out,
  )