"""Generate Reva.xcodeproj using only Python; no global tooling install required."""
from pathlib import Path
import hashlib

root = Path(__file__).resolve().parents[1]
app = root / "apps/ios/Reva"
project = root / "Reva.xcodeproj"
project.mkdir(exist_ok=True)

def ident(value): return hashlib.sha1(value.encode()).hexdigest()[:24].upper()
def quote(value): return '"' + str(value).replace('\\', '\\\\').replace('"', '\\"') + '"'
def seq(items): return '(' + ', '.join(items) + ', )' if items else '()'

objects = []
def obj(key, body): objects.append(f'{ident(key)} = {{ {body} }};'); return ident(key)
source_refs, source_builds, resource_refs, resource_builds = [], [], [], []
for path in sorted(app.rglob('*')):
    if not path.is_file() or path.name.startswith('.') or path.suffix not in ['.swift', '.json', '.txt', '.pdf', '.wav', '.m4a', '.png']:
        continue
    rel = path.relative_to(root).as_posix()
    filetype = 'sourcecode.swift' if path.suffix == '.swift' else 'file'
    ref = obj(rel, f'isa = PBXFileReference; lastKnownFileType = {filetype}; path = {quote(rel)}; sourceTree = SOURCE_ROOT;')
    build = obj('build:'+rel, f'isa = PBXBuildFile; fileRef = {ref};')
    if path.suffix == '.swift': source_refs.append(ref); source_builds.append(build)
    else: resource_refs.append(ref); resource_builds.append(build)
product = obj('product','isa = PBXFileReference; explicitFileType = wrapper.application; path = Reva.app; sourceTree = BUILT_PRODUCTS_DIR;')
main_group = obj('group',f'isa = PBXGroup; children = {seq(source_refs+resource_refs+[ident("products")])}; sourceTree = "<group>";')
products = obj('products',f'isa = PBXGroup; children = ({product}, ); name = Products; sourceTree = "<group>";')
sources = obj('sources',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {seq(source_builds)}; runOnlyForDeploymentPostprocessing = 0;')
resources = obj('resources',f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {seq(resource_builds)}; runOnlyForDeploymentPostprocessing = 0;')
frameworks = obj('frameworks','isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
config_ids = []
for configuration in ['Debug','Release']:
    settings = {
        'PRODUCT_BUNDLE_IDENTIFIER':'health.revamed.Reva', 'PRODUCT_NAME':'Reva',
        'SWIFT_VERSION':'5.0', 'IPHONEOS_DEPLOYMENT_TARGET':'18.0', 'SDKROOT':'iphoneos',
        'SUPPORTED_PLATFORMS':'iphoneos iphonesimulator', 'TARGETED_DEVICE_FAMILY':'1',
        'INFOPLIST_FILE':'apps/ios/Reva/Info.plist', 'CODE_SIGN_STYLE':'Automatic',
        'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if configuration=='Debug' else '-O',
        'DEBUG_INFORMATION_FORMAT':'dwarf', 'ENABLE_USER_SCRIPT_SANDBOXING':'YES',
        'ASSETCATALOG_COMPILER_APPICON_NAME':'', 'CURRENT_PROJECT_VERSION':'1',
        'MARKETING_VERSION':'0.1.0', 'GENERATE_INFOPLIST_FILE':'NO', 'ALWAYS_SEARCH_USER_PATHS':'NO',
    }
    config_ids.append(obj('config:'+configuration, 'isa = XCBuildConfiguration; buildSettings = {' + ''.join(f'{k} = {quote(v)};' for k,v in settings.items()) + f'}}; name = {configuration};'))
config = obj('configList',f'isa = XCConfigurationList; buildConfigurations = {seq(config_ids)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug;')
target = obj('target',f'isa = PBXNativeTarget; buildConfigurationList = {config}; buildPhases = ({sources}, {frameworks}, {resources}, ); buildRules = (); dependencies = (); name = Reva; productName = Reva; productReference = {product}; productType = "com.apple.product-type.application";')
project_id = obj('project',f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2640; }}; buildConfigurationList = {config}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base, ); mainGroup = {main_group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({target}, );')
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+f'\n}}; rootObject = {project_id}; }}\n')
scheme_dir = project/'xcshareddata/xcschemes'; scheme_dir.mkdir(parents=True,exist_ok=True)
reference=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Reva.app" BlueprintName="Reva" ReferencedContainer="container:Reva.xcodeproj"/>'
(scheme_dir/'Reva.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2640" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"/><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>
''')
print(f'Generated {project}: {len(source_refs)} Swift files, {len(resource_refs)} resources')
