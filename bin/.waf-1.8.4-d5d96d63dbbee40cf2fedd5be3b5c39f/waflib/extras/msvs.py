#! /usr/bin/env python
# encoding: utf-8
# WARNING! Do not edit! http://waf.googlecode.com/git/docs/wafbook/single.html#_obtaining_the_waf_file

import os,re,sys
import uuid
from waflib.Build import BuildContext
from waflib import Utils,TaskGen,Logs,Task,Context,Node,Options
HEADERS_GLOB='**/(*.h|*.hpp|*.H|*.inl)'
PROJECT_TEMPLATE=r'''<?xml version="1.0" encoding="UTF-8"?>
<Project DefaultTargets="Build" ToolsVersion="4.0"
	xmlns="http://schemas.microsoft.com/developer/msbuild/2003">

	<ItemGroup Label="ProjectConfigurations">
		${for b in project.build_properties}
		<ProjectConfiguration Include="${b.configuration}|${b.platform}">
			<Configuration>${b.configuration}</Configuration>
			<Platform>${b.platform}</Platform>
		</ProjectConfiguration>
		${endfor}
	</ItemGroup>

	<PropertyGroup Label="Globals">
		<ProjectGuid>{${project.uuid}}</ProjectGuid>
		<Keyword>MakeFileProj</Keyword>
		<ProjectName>${project.name}</ProjectName>
	</PropertyGroup>
	<Import Project="$(VCTargetsPath)\Microsoft.Cpp.Default.props" />

	${for b in project.build_properties}
	<PropertyGroup Condition="'$(Configuration)|$(Platform)'=='${b.configuration}|${b.platform}'" Label="Configuration">
		<ConfigurationType>Makefile</ConfigurationType>
		<OutDir>${b.outdir}</OutDir>
		<PlatformToolset>v110</PlatformToolset>
	</PropertyGroup>
	${endfor}

	<Import Project="$(VCTargetsPath)\Microsoft.Cpp.props" />
	<ImportGroup Label="ExtensionSettings">
	</ImportGroup>

	${for b in project.build_properties}
	<ImportGroup Label="PropertySheets" Condition="'$(Configuration)|$(Platform)'=='${b.configuration}|${b.platform}'">
		<Import Project="$(UserRootDir)\Microsoft.Cpp.$(Platform).user.props" Condition="exists('$(UserRootDir)\Microsoft.Cpp.$(Platform).user.props')" Label="LocalAppDataPlatform" />
	</ImportGroup>
	${endfor}

	${for b in project.build_properties}
	<PropertyGroup Condition="'$(Configuration)|$(Platform)'=='${b.configuration}|${b.platform}'">
		<NMakeBuildCommandLine>${xml:project.get_build_command(b)}</NMakeBuildCommandLine>
		<NMakeReBuildCommandLine>${xml:project.get_rebuild_command(b)}</NMakeReBuildCommandLine>
		<NMakeCleanCommandLine>${xml:project.get_clean_command(b)}</NMakeCleanCommandLine>
		<NMakeIncludeSearchPath>${xml:b.includes_search_path}</NMakeIncludeSearchPath>
		<NMakePreprocessorDefinitions>${xml:b.preprocessor_definitions};$(NMakePreprocessorDefinitions)</NMakePreprocessorDefinitions>
		<IncludePath>${xml:b.includes_search_path}</IncludePath>
		<ExecutablePath>$(ExecutablePath)</ExecutablePath>

		${if getattr(b, 'output_file', None)}
		<NMakeOutput>${xml:b.output_file}</NMakeOutput>
		${endif}
		${if getattr(b, 'deploy_dir', None)}
		<RemoteRoot>${xml:b.deploy_dir}</RemoteRoot>
		${endif}
	</PropertyGroup>
	${endfor}

	${for b in project.build_properties}
		${if getattr(b, 'deploy_dir', None)}
	<ItemDefinitionGroup Condition="'$(Configuration)|$(Platform)'=='${b.configuration}|${b.platform}'">
		<Deploy>
			<DeploymentType>CopyToHardDrive</DeploymentType>
		</Deploy>
	</ItemDefinitionGroup>
		${endif}
	${endfor}

	<ItemGroup>
		${for x in project.source}
		<${project.get_key(x)} Include='${x.abspath()}' />
		${endfor}
	</ItemGroup>
	<Import Project="$(VCTargetsPath)\Microsoft.Cpp.targets" />
	<ImportGroup Label="ExtensionTargets">
	</ImportGroup>
</Project>
'''
FILTER_TEMPLATE='''<?xml version="1.0" encoding="UTF-8"?>
<Project ToolsVersion="4.0" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
	<ItemGroup>
		${for x in project.source}
			<${project.get_key(x)} Include="${x.abspath()}">
				<Filter>${project.get_filter_name(x.parent)}</Filter>
			</${project.get_key(x)}>
		${endfor}
	</ItemGroup>
	<ItemGroup>
		${for x in project.dirs()}
			<Filter Include="${project.get_filter_name(x)}">
				<UniqueIdentifier>{${project.make_uuid(x.abspath())}}</UniqueIdentifier>
			</Filter>
		${endfor}
	</ItemGroup>
</Project>
'''
PROJECT_2008_TEMPLATE=r'''<?xml version="1.0" encoding="UTF-8"?>
<VisualStudioProject ProjectType="Visual C++" Version="9,00"
	Name="${xml: project.name}" ProjectGUID="{${project.uuid}}"
	Keyword="MakeFileProj"
	TargetFrameworkVersion="196613">
	<Platforms>
		${if project.build_properties}
		${for b in project.build_properties}
		   <Platform Name="${xml: b.platform}" />
		${endfor}
		${else}
		   <Platform Name="Win32" />
		${endif}
	</Platforms>
	<ToolFiles>
	</ToolFiles>
	<Configurations>
		${if project.build_properties}
		${for b in project.build_properties}
		<Configuration
			Name="${xml: b.configuration}|${xml: b.platform}"
			IntermediateDirectory="$ConfigurationName"
			OutputDirectory="${xml: b.outdir}"
			ConfigurationType="0">
			<Tool
				Name="VCNMakeTool"
				BuildCommandLine="${xml: project.get_build_command(b)}"
				ReBuildCommandLine="${xml: project.get_rebuild_command(b)}"
				CleanCommandLine="${xml: project.get_clean_command(b)}"
				${if getattr(b, 'output_file', None)}
				Output="${xml: b.output_file}"
				${endif}
				PreprocessorDefinitions="${xml: b.preprocessor_definitions}"
				IncludeSearchPath="${xml: b.includes_search_path}"
				ForcedIncludes=""
				ForcedUsingAssemblies=""
				AssemblySearchPath=""
				CompileAsManaged=""
			/>
		</Configuration>
		${endfor}
		${else}
			<Configuration Name="Release|Win32" >
		</Configuration>
		${endif}
	</Configurations>
	<References>
	</References>
	<Files>
${project.display_filter()}
	</Files>
</VisualStudioProject>
'''
SOLUTION_TEMPLATE='''Microsoft Visual Studio Solution File, Format Version ${project.numver}
# Visual Studio ${project.vsver}
${for p in project.all_projects}
Project("{${p.ptype()}}") = "${p.name}", "${p.title}", "{${p.uuid}}"
EndProject${endfor}
Global
	GlobalSection(SolutionConfigurationPlatforms) = preSolution
		${if project.all_projects}
		${for (configuration, platform) in project.all_projects[0].ctx.project_configurations()}
		${configuration}|${platform} = ${configuration}|${platform}
		${endfor}
		${endif}
	EndGlobalSection
	GlobalSection(ProjectConfigurationPlatforms) = postSolution
		${for p in project.all_projects}
			${if hasattr(p, 'source')}
			${for b in p.build_properties}
		{${p.uuid}}.${b.configuration}|${b.platform}.ActiveCfg = ${b.configuration}|${b.platform}
			${if getattr(p, 'is_active', None)}
		{${p.uuid}}.${b.configuration}|${b.platform}.Build.0 = ${b.configuration}|${b.platform}
			${endif}
			${if getattr(p, 'is_deploy', None)}
		{${p.uuid}}.${b.configuration}|${b.platform}.Deploy.0 = ${b.configuration}|${b.platform}
			${endif}
			${endfor}
			${endif}
		${endfor}
	EndGlobalSection
	GlobalSection(SolutionProperties) = preSolution
		HideSolutionNode = FALSE
	EndGlobalSection
	GlobalSection(NestedProjects) = preSolution
	${for p in project.all_projects}
		${if p.parent}
		{${p.uuid}} = {${p.parent.uuid}}
		${endif}
	${endfor}
	EndGlobalSection
EndGlobal
'''
COMPILE_TEMPLATE='''def f(project):
	lst = []
	def xml_escape(value):
		return value.replace("&", "&amp;").replace('"', "&quot;").replace("'", "&apos;").replace("<", "&lt;").replace(">", "&gt;")

	%s

	#f = open('cmd.txt', 'w')
	#f.write(str(lst))
	#f.close()
	return ''.join(lst)
'''
reg_act=re.compile(r"(?P<backslash>\\)|(?P<dollar>\$\$)|(?P<subst>\$\{(?P<code>[^}]*?)\})",re.M)
def compile_template(line):
	extr=[]
	def repl(match):
		g=match.group
		if g('dollar'):return"$"
		elif g('backslash'):
			return"\\"
		elif g('subst'):
			extr.append(g('code'))
			return"<<|@|>>"
		return None
	line2=reg_act.sub(repl,line)
	params=line2.split('<<|@|>>')
	assert(extr)
	indent=0
	buf=[]
	app=buf.append
	def app(txt):
		buf.append(indent*'\t'+txt)
	for x in range(len(extr)):
		if params[x]:
			app("lst.append(%r)"%params[x])
		f=extr[x]
		if f.startswith('if')or f.startswith('for'):
			app(f+':')
			indent+=1
		elif f.startswith('py:'):
			app(f[3:])
		elif f.startswith('endif')or f.startswith('endfor'):
			indent-=1
		elif f.startswith('else')or f.startswith('elif'):
			indent-=1
			app(f+':')
			indent+=1
		elif f.startswith('xml:'):
			app('lst.append(xml_escape(%s))'%f[4:])
		else:
			app('lst.append(%s)'%f)
	if extr:
		if params[-1]:
			app("lst.append(%r)"%params[-1])
	fun=COMPILE_TEMPLATE%"\n\t".join(buf)
	return Task.funex(fun)
re_blank=re.compile('(\n|\r|\\s)*\n',re.M)
def rm_blank_lines(txt):
	txt=re_blank.sub('\r\n',txt)
	return txt
BOM='\xef\xbb\xbf'
try:
	BOM=bytes(BOM,'iso8859-1')
except TypeError:
	pass
def stealth_write(self,data,flags='wb'):
	try:
		x=unicode
	except NameError:
		data=data.encode('utf-8')
	else:
		data=data.decode(sys.getfilesystemencoding(),'replace')
		data=data.encode('utf-8')
	if self.name.endswith('.vcproj')or self.name.endswith('.vcxproj'):
		data=BOM+data
	try:
		txt=self.read(flags='rb')
		if txt!=data:
			raise ValueError('must write')
	except(IOError,ValueError):
		self.write(data,flags=flags)
	else:
		Logs.debug('msvs: skipping %s'%self.abspath())
Node.Node.stealth_write=stealth_write
re_quote=re.compile("[^a-zA-Z0-9-]")
def quote(s):
	return re_quote.sub("_",s)
def xml_escape(value):
	return value.replace("&","&amp;").replace('"',"&quot;").replace("'","&apos;").replace("<","&lt;").replace(">","&gt;")
def make_uuid(v,prefix=None):
	if isinstance(v,dict):
		keys=list(v.keys())
		keys.sort()
		tmp=str([(k,v[k])for k in keys])
	else:
		tmp=str(v)
	d=Utils.md5(tmp).hexdigest().upper()
	if prefix:
		d='%s%s'%(prefix,d[8:])
	gid=uuid.UUID(d,version=4)
	return str(gid).upper()
def diff(node,fromnode):
	c1=node
	c2=fromnode
	c1h=c1.height()
	c2h=c2.height()
	lst=[]
	up=0
	while c1h>c2h:
		lst.append(c1.name)
		c1=c1.parent
		c1h-=1
	while c2h>c1h:
		up+=1
		c2=c2.parent
		c2h-=1
	while id(c1)!=id(c2):
		lst.append(c1.name)
		up+=1
		c1=c1.parent
		c2=c2.parent
	for i in range(up):
		lst.append('(..)')
	lst.reverse()
	return tuple(lst)
class build_property(object):
	pass
class vsnode(object):
	def __init__(self,ctx):
		self.ctx=ctx
		self.name=''
		self.vspath=''
		self.uuid=''
		self.parent=None
	def get_waf(self):
		return'cd /d "%s" & %s'%(self.ctx.srcnode.abspath(),getattr(self.ctx,'waf_command','waf.bat'))
	def ptype(self):
		pass
	def write(self):
		pass
	def make_uuid(self,val):
		return make_uuid(val)
class vsnode_vsdir(vsnode):
	VS_GUID_SOLUTIONFOLDER="2150E333-8FDC-42A3-9474-1A3956D46DE8"
	def __init__(self,ctx,uuid,name,vspath=''):
		vsnode.__init__(self,ctx)
		self.title=self.name=name
		self.uuid=uuid
		self.vspath=vspath or name
	def ptype(self):
		return self.VS_GUID_SOLUTIONFOLDER
class vsnode_project(vsnode):
	VS_GUID_VCPROJ="8BC9CEB8-8B4A-11D0-8D11-00A0C91BC942"
	def ptype(self):
		return self.VS_GUID_VCPROJ
	def __init__(self,ctx,node):
		vsnode.__init__(self,ctx)
		self.path=node
		self.uuid=make_uuid(node.abspath())
		self.name=node.name
		self.title=self.path.abspath()
		self.source=[]
		self.build_properties=[]
	def dirs(self):
		lst=[]
		def add(x):
			if x.height()>self.tg.path.height()and x not in lst:
				lst.append(x)
				add(x.parent)
		for x in self.source:
			add(x.parent)
		return lst
	def write(self):
		Logs.debug('msvs: creating %r'%self.path)
		template1=compile_template(PROJECT_TEMPLATE)
		proj_str=template1(self)
		proj_str=rm_blank_lines(proj_str)
		self.path.stealth_write(proj_str)
		template2=compile_template(FILTER_TEMPLATE)
		filter_str=template2(self)
		filter_str=rm_blank_lines(filter_str)
		tmp=self.path.parent.make_node(self.path.name+'.filters')
		tmp.stealth_write(filter_str)
	def get_key(self,node):
		name=node.name
		if name.endswith('.cpp')or name.endswith('.c'):
			return'ClCompile'
		return'ClInclude'
	def collect_properties(self):
		ret=[]
		for c in self.ctx.configurations:
			for p in self.ctx.platforms:
				x=build_property()
				x.outdir=''
				x.configuration=c
				x.platform=p
				x.preprocessor_definitions=''
				x.includes_search_path=''
				ret.append(x)
		self.build_properties=ret
	def get_build_params(self,props):
		opt='--execsolution=%s'%self.ctx.get_solution_node().abspath()
		return(self.get_waf(),opt)
	def get_build_command(self,props):
		return"%s build %s"%self.get_build_params(props)
	def get_clean_command(self,props):
		return"%s clean %s"%self.get_build_params(props)
	def get_rebuild_command(self,props):
		return"%s clean build %s"%self.get_build_params(props)
	def get_filter_name(self,node):
		lst=diff(node,self.tg.path)
		return'\\'.join(lst)or'.'
class vsnode_alias(vsnode_project):
	def __init__(self,ctx,node,name):
		vsnode_project.__init__(self,ctx,node)
		self.name=name
		self.output_file=''
class vsnode_build_all(vsnode_alias):
	def __init__(self,ctx,node,name='build_all_projects'):
		vsnode_alias.__init__(self,ctx,node,name)
		self.is_active=True
class vsnode_install_all(vsnode_alias):
	def __init__(self,ctx,node,name='install_all_projects'):
		vsnode_alias.__init__(self,ctx,node,name)
	def get_build_command(self,props):
		return"%s build install %s"%self.get_build_params(props)
	def get_clean_command(self,props):
		return"%s clean %s"%self.get_build_params(props)
	def get_rebuild_command(self,props):
		return"%s clean build install %s"%self.get_build_params(props)
class vsnode_project_view(vsnode_alias):
	def __init__(self,ctx,node,name='project_view'):
		vsnode_alias.__init__(self,ctx,node,name)
		self.tg=self.ctx()
		self.exclude_files=Node.exclude_regs+'''
waf-1.8.*
waf3-1.8.*/**
.waf-1.8.*
.waf3-1.8.*/**
**/*.sdf
**/*.suo
**/*.ncb
**/%s
		'''%Options.lockfile
	def collect_source(self):
		self.source=self.ctx.srcnode.ant_glob('**',excl=self.exclude_files)
	def get_build_command(self,props):
		params=self.get_build_params(props)+(self.ctx.cmd,)
		return"%s %s %s"%params
	def get_clean_command(self,props):
		return""
	def get_rebuild_command(self,props):
		return self.get_build_command(props)
class vsnode_target(vsnode_project):
	def __init__(self,ctx,tg):
		base=getattr(ctx,'projects_dir',None)or tg.path
		node=base.make_node(quote(tg.name)+ctx.project_extension)
		vsnode_project.__init__(self,ctx,node)
		self.name=quote(tg.name)
		self.tg=tg
	def get_build_params(self,props):
		opt='--execsolution=%s'%self.ctx.get_solution_node().abspath()
		if getattr(self,'tg',None):
			opt+=" --targets=%s"%self.tg.name
		return(self.get_waf(),opt)
	def collect_source(self):
		tg=self.tg
		source_files=tg.to_nodes(getattr(tg,'source',[]))
		include_dirs=Utils.to_list(getattr(tg,'msvs_includes',[]))
		include_files=[]
		for x in include_dirs:
			if isinstance(x,str):
				x=tg.path.find_node(x)
			if x:
				lst=[y for y in x.ant_glob(HEADERS_GLOB,flat=False)]
				include_files.extend(lst)
		self.source.extend(list(set(source_files+include_files)))
		self.source.sort(key=lambda x:x.abspath())
	def collect_properties(self):
		super(vsnode_target,self).collect_properties()
		for x in self.build_properties:
			x.outdir=self.path.parent.abspath()
			x.preprocessor_definitions=''
			x.includes_search_path=''
			try:
				tsk=self.tg.link_task
			except AttributeError:
				pass
			else:
				x.output_file=tsk.outputs[0].abspath()
				x.preprocessor_definitions=';'.join(tsk.env.DEFINES)
				x.includes_search_path=';'.join(self.tg.env.INCPATHS)
class msvs_generator(BuildContext):
	'''generates a visual studio 2010 solution'''
	cmd='msvs'
	fun='build'
	def init(self):
		if not getattr(self,'configurations',None):
			self.configurations=['Release']
		if not getattr(self,'platforms',None):
			self.platforms=['Win32']
		if not getattr(self,'all_projects',None):
			self.all_projects=[]
		if not getattr(self,'project_extension',None):
			self.project_extension='.vcxproj'
		if not getattr(self,'projects_dir',None):
			self.projects_dir=self.srcnode.make_node('.depproj')
			self.projects_dir.mkdir()
		if not getattr(self,'vsnode_vsdir',None):
			self.vsnode_vsdir=vsnode_vsdir
		if not getattr(self,'vsnode_target',None):
			self.vsnode_target=vsnode_target
		if not getattr(self,'vsnode_build_all',None):
			self.vsnode_build_all=vsnode_build_all
		if not getattr(self,'vsnode_install_all',None):
			self.vsnode_install_all=vsnode_install_all
		if not getattr(self,'vsnode_project_view',None):
			self.vsnode_project_view=vsnode_project_view
		self.numver='11.00'
		self.vsver='2010'
	def execute(self):
		self.restore()
		if not self.all_envs:
			self.load_envs()
		self.recurse([self.run_dir])
		self.init()
		self.collect_projects()
		self.write_files()
	def collect_projects(self):
		self.collect_targets()
		self.add_aliases()
		self.collect_dirs()
		default_project=getattr(self,'default_project',None)
		def sortfun(x):
			if x.name==default_project:
				return''
			return getattr(x,'path',None)and x.path.abspath()or x.name
		self.all_projects.sort(key=sortfun)
	def write_files(self):
		for p in self.all_projects:
			p.write()
		node=self.get_solution_node()
		node.parent.mkdir()
		Logs.warn('Creating %r'%node)
		template1=compile_template(SOLUTION_TEMPLATE)
		sln_str=template1(self)
		sln_str=rm_blank_lines(sln_str)
		node.stealth_write(sln_str)
	def get_solution_node(self):
		try:
			return self.solution_node
		except AttributeError:
			pass
		solution_name=getattr(self,'solution_name',None)
		if not solution_name:
			solution_name=getattr(Context.g_module,Context.APPNAME,'project')+'.sln'
		if os.path.isabs(solution_name):
			self.solution_node=self.root.make_node(solution_name)
		else:
			self.solution_node=self.srcnode.make_node(solution_name)
		return self.solution_node
	def project_configurations(self):
		ret=[]
		for c in self.configurations:
			for p in self.platforms:
				ret.append((c,p))
		return ret
	def collect_targets(self):
		for g in self.groups:
			for tg in g:
				if not isinstance(tg,TaskGen.task_gen):
					continue
				if not hasattr(tg,'msvs_includes'):
					tg.msvs_includes=tg.to_list(getattr(tg,'includes',[]))+tg.to_list(getattr(tg,'export_includes',[]))
				tg.post()
				if not getattr(tg,'link_task',None):
					continue
				p=self.vsnode_target(self,tg)
				p.collect_source()
				p.collect_properties()
				self.all_projects.append(p)
	def add_aliases(self):
		base=getattr(self,'projects_dir',None)or self.tg.path
		node_project=base.make_node('build_all_projects'+self.project_extension)
		p_build=self.vsnode_build_all(self,node_project)
		p_build.collect_properties()
		self.all_projects.append(p_build)
		node_project=base.make_node('install_all_projects'+self.project_extension)
		p_install=self.vsnode_install_all(self,node_project)
		p_install.collect_properties()
		self.all_projects.append(p_install)
		node_project=base.make_node('project_view'+self.project_extension)
		p_view=self.vsnode_project_view(self,node_project)
		p_view.collect_source()
		p_view.collect_properties()
		self.all_projects.append(p_view)
		n=self.vsnode_vsdir(self,make_uuid(self.srcnode.abspath()+'build_aliases'),"build_aliases")
		p_build.parent=p_install.parent=p_view.parent=n
		self.all_projects.append(n)
	def collect_dirs(self):
		seen={}
		def make_parents(proj):
			if getattr(proj,'parent',None):
				return
			x=proj.iter_path
			if x in seen:
				proj.parent=seen[x]
				return
			n=proj.parent=seen[x]=self.vsnode_vsdir(self,make_uuid(x.abspath()),x.name)
			n.iter_path=x.parent
			self.all_projects.append(n)
			if x.height()>self.srcnode.height()+1:
				make_parents(n)
		for p in self.all_projects[:]:
			if not getattr(p,'tg',None):
				continue
			p.iter_path=p.tg.path
			make_parents(p)
def wrap_2008(cls):
	class dec(cls):
		def __init__(self,*k,**kw):
			cls.__init__(self,*k,**kw)
			self.project_template=PROJECT_2008_TEMPLATE
		def display_filter(self):
			root=build_property()
			root.subfilters=[]
			root.sourcefiles=[]
			root.source=[]
			root.name=''
			@Utils.run_once
			def add_path(lst):
				if not lst:
					return root
				child=build_property()
				child.subfilters=[]
				child.sourcefiles=[]
				child.source=[]
				child.name=lst[-1]
				par=add_path(lst[:-1])
				par.subfilters.append(child)
				return child
			for x in self.source:
				tmp=self.get_filter_name(x.parent)
				tmp=tmp!='.'and tuple(tmp.split('\\'))or()
				par=add_path(tmp)
				par.source.append(x)
			def display(n):
				buf=[]
				for x in n.source:
					buf.append('<File RelativePath="%s" FileType="%s"/>\n'%(xml_escape(x.abspath()),self.get_key(x)))
				for x in n.subfilters:
					buf.append('<Filter Name="%s">'%xml_escape(x.name))
					buf.append(display(x))
					buf.append('</Filter>')
				return'\n'.join(buf)
			return display(root)
		def get_key(self,node):
			return''
		def write(self):
			Logs.debug('msvs: creating %r'%self.path)
			template1=compile_template(self.project_template)
			proj_str=template1(self)
			proj_str=rm_blank_lines(proj_str)
			self.path.stealth_write(proj_str)
	return dec
class msvs_2008_generator(msvs_generator):
	'''generates a visual studio 2008 solution'''
	cmd='msvs2008'
	fun=msvs_generator.fun
	def init(self):
		if not getattr(self,'project_extension',None):
			self.project_extension='_2008.vcproj'
		if not getattr(self,'solution_name',None):
			self.solution_name=getattr(Context.g_module,Context.APPNAME,'project')+'_2008.sln'
		if not getattr(self,'vsnode_target',None):
			self.vsnode_target=wrap_2008(vsnode_target)
		if not getattr(self,'vsnode_build_all',None):
			self.vsnode_build_all=wrap_2008(vsnode_build_all)
		if not getattr(self,'vsnode_install_all',None):
			self.vsnode_install_all=wrap_2008(vsnode_install_all)
		if not getattr(self,'vsnode_project_view',None):
			self.vsnode_project_view=wrap_2008(vsnode_project_view)
		msvs_generator.init(self)
		self.numver='10.00'
		self.vsver='2008'
def options(ctx):
	ctx.add_option('--execsolution',action='store',help='when building with visual studio, use a build state file')
	old=BuildContext.execute
	def override_build_state(ctx):
		def lock(rm,add):
			uns=ctx.options.execsolution.replace('.sln',rm)
			uns=ctx.root.make_node(uns)
			try:
				uns.delete()
			except OSError:
				pass
			uns=ctx.options.execsolution.replace('.sln',add)
			uns=ctx.root.make_node(uns)
			try:
				uns.write('')
			except EnvironmentError:
				pass
		if ctx.options.execsolution:
			ctx.launch_dir=Context.top_dir
			lock('.lastbuildstate','.unsuccessfulbuild')
			old(ctx)
			lock('.unsuccessfulbuild','.lastbuildstate')
		else:
			old(ctx)
	BuildContext.execute=override_build_state
