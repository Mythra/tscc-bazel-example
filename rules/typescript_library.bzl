"""A rule helpy for typescript library.
"""

load(
  '@build_bazel_rules_nodejs//:providers.bzl',
  'DeclarationInfo',
  'ExternalNpmPackageInfo',
  'declaration_info',
  'js_module_info',
  'run_node',
)
load(
  '//rules:write_typescript_config.bzl',
  'write_typescript_config',
)
load(
  '//rules:write_tscc_config.bzl',
  'write_tscc_config',
)

def _is_ts_src(src):
  if not src.endswith('.d.ts') and (src.endswith('.ts') or src.endswith('.tsx')):
    return True
  return False

def _join(*elements):
  segments = [f for f in elements if f]
  if len(segments):
    return '/'.join(segments)
  return '.'

def _calculate_root_dir(ctx):
  some_generated_path = None
  some_source_path = None
  root_path = None

  for src in ctx.files.srcs:
    if _is_ts_src(src.path):
      if src.is_source:
        some_source_path = src.path
      else:
        some_generated_path = src.path
        root_path = ctx.bin_dir.path

  if some_source_path and some_generated_path:
    fail('ERROR: %s srcs cannot be a mix of generated files and source files ' % ctx.label +
         'since this would prevent giving a single rootDir to the TypeScript compiler\n' +
         '    found generated file %s and source file %s' %
         (some_generated_path, some_source_path))

  return _join(
    root_path,
    ctx.label.workspace_root,
    ctx.label.package,
    ctx.attr.root_dir,
  )

def _typescript_library_impl(ctx):
  tscc_arguments = [
    '--spec',
    ctx.file.tscc_config.path,
  ]
  typescript_args = [
    '--project',
    ctx.file.ts_config.path,
    '--outDir',
    _join(ctx.bin_dir.path, ctx.label.workspace_root, ctx.label.package, ctx.attr.out_dir),
    '--rootDir',
    _calculate_root_dir(ctx),
  ]
  closure_compiler_args = [
    '--define',
    'BUILD_VERSION="' + ctx.var['VERSION'] + '"'
  ]

  if 'VERBOSE_LOGS' in ctx.var.keys():
    typescript_args += [
      # What files were in the ts.Program
      '--listFiles',
      # Did tsc write all outputs to the place we expect to find them?
      '--listEmittedFiles',
      # Why did module resolution fail?
      '--traceResolution',
      # Why was the build slow?
      '--diagnostics',
      '--extendedDiagnostics',
    ]
    closure_compiler_args += [
      '--warning_level',
      'VERBOSE',
      '--debug',
    ]
  
  deps_depsets = []
  inputs = ctx.files.srcs[:]
  for dep in ctx.attr.deps:
    if ExternalNpmPackageInfo in dep:
      # TODO: we could maybe filter these to be tsconfig.json or *.d.ts only
      # we don't expect tsc wants to read any other files from npm packages.
      deps_depsets.append(dep[ExternalNpmPackageInfo].sources)
    if DeclarationInfo in dep:
      deps_depsets.append(dep[DeclarationInfo].transitive_declarations)
  inputs.extend(depset(transitive = deps_depsets).to_list())
  inputs.append(ctx.file.ts_config)
  inputs.append(ctx.file.tscc_config)
  
  outputs = ctx.outputs.js_outs
  runtime_outputs = ctx.outputs.js_outs
  typings_outputs = [s for s in ctx.files.srcs if s.path.endswith(".d.ts")]
  default_outputs_depset = depset(runtime_outputs) if len(runtime_outputs) else depset(typings_outputs)

  final_args = tscc_arguments
  final_args.append('--')
  final_args += typescript_args
  final_args.append('--')
  final_args += closure_compiler_args
  
  if len(outputs) > 0:
    run_node(
      ctx,
      inputs = inputs,
      arguments = final_args,
      outputs = outputs,
      mnemonic = 'TSCC',
      executable = '_tscc_bin',
      progress_message = 'Compiling TypeScript Library %s [tscc -p %s]' % (
        ctx.label,
        ctx.file.ts_config.short_path,
      ),
    )

  providers = [
    DefaultInfo(
      files = default_outputs_depset,
      runfiles = ctx.runfiles(
        transitive_files = depset(ctx.files.data, transitive = [
          default_outputs_depset,
        ]),
        collect_default = True,
      ),
    ),
    js_module_info(
      sources = depset(runtime_outputs),
      deps = ctx.attr.deps,
    ),
    coverage_common.instrumented_files_info(
      ctx,
      source_attributes = ['srcs'],
      dependency_attributes = ['deps'],
      extensions = ['ts', 'tsx'],
    ),
  ]

  # Only provide DeclarationInfo if there are some typings.
  # Improves error messaging if a ts_project needs declaration = True
  typings_in_deps = [d for d in ctx.attr.deps if DeclarationInfo in d]
  if len(typings_outputs) or len(typings_in_deps):
    providers.append(declaration_info(depset(typings_outputs), typings_in_deps))
    providers.append(OutputGroupInfo(types = depset(typings_outputs)))

  return providers

typescript_library_rule = rule(
  implementation = _typescript_library_impl,
  attrs = {
    'data': attr.label_list(default = [], allow_files = True),
    'deps': attr.label_list(),
    'out_dir': attr.string(),
    'root_dir': attr.string(),
    'srcs': attr.label_list(allow_files = True, mandatory = True),
    'ts_config': attr.label(mandatory = True, allow_single_file = [".json"]),
    'tscc_config': attr.label(mandatory = True, allow_single_file = [".json"]),
    'js_outs': attr.output_list(),
    '_tscc_bin': attr.label(
      default = Label('//rules:tscc'),
      executable = True,
      cfg = 'host',
    ),
  },
)

def typescript_library(
  name,
  module_name,
  entrypoint,
  srcs = [],
  data = [],
  deps = [],
  out_dir = None,
  root_dir = None,
  **kwargs
):
  """A macro wrapper around typescript rule to build

  Args:
    name: the name of the rule to build
    entrypoint: entrypoint for the bundle
    module_name: the name of the module
    srcs: the source files to compile
    data: the extra data files to include
    deps: the extra dependencies for this project
    out_dir: an output directory
    root_dir: the root directory of source files
    **kwargs: extra arguments
  """
  if entrypoint not in srcs:
    fail('entrypoint needs to be in srcs')

  tsconfig_name = 'tsconfig_%s.json' % name
  tscc_config_name = 'tscc_config_%s.json' % name
  write_typescript_config(
    name = '_gen_tsconfig_%s' % name,
    config = {
      'compilerOptions': {
        'target': 'es5',
        'module': 'commonjs',
        'moduleResolution': 'node',
        'isolatedModules': False,
        'experimentalDecorators': True,
        'emitDecoratorMetadata': True,
        'noImplicitAny': True,
        'removeComments': False,
        'preserveConstEnums': True,
        'lib': ['dom', 'es2015'],
      },
    },
    files = [s for s in srcs if _is_ts_src(s)],
    out = tsconfig_name,
  )
  write_tscc_config(
    name = '_gen_tscconfig_%s' % name,
    config = {
      'modules': {
        module_name: native.package_name() + '/' + entrypoint,
      },
      'compilerFlags': {
        'env': 'BROWSER',
        'compilation_level': 'ADVANCED',
      },
    },
    out = tscc_config_name,
  )
  js_outs = [module_name + '.js']

  typescript_library_rule(
    name = name,
    data = data,
    deps = deps,
    out_dir = out_dir,
    root_dir = root_dir,
    srcs = srcs,
    ts_config = tsconfig_name,
    tscc_config = tscc_config_name,
    js_outs = js_outs,
    **kwargs
  )