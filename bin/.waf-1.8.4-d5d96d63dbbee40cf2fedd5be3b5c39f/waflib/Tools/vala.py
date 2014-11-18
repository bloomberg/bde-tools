#! /usr/bin/env python
# encoding: utf-8
# WARNING! Do not edit! http://waf.googlecode.com/git/docs/wafbook/single.html#_obtaining_the_waf_file

import os.path,shutil,re
from waflib import Context,Task,Utils,Logs,Options,Errors
from waflib.TaskGen import extension,taskgen_method
from waflib.Configure import conf
class valac(Task.Task):
	vars=["VALAC","VALAC_VERSION","VALAFLAGS"]
	ext_out=['.h']
	def run(self):
		cmd=self.env.VALAC+self.env.VALAFLAGS
		cmd.extend([a.abspath()for a in self.inputs])
		ret=self.exec_command(cmd,cwd=self.outputs[0].parent.abspath())
		if ret:
			return ret
		for x in self.outputs:
			if id(x.parent)!=id(self.outputs[0].parent):
				shutil.move(self.outputs[0].parent.abspath()+os.sep+x.name,x.abspath())
		if self.generator.dump_deps_node:
			self.generator.dump_deps_node.write('\n'.join(self.generator.packages))
		return ret
valac=Task.update_outputs(valac)
@taskgen_method
def init_vala_task(self):
	self.profile=getattr(self,'profile','gobject')
	if self.profile=='gobject':
		self.uselib=Utils.to_list(getattr(self,'uselib',[]))
		if not'GOBJECT'in self.uselib:
			self.uselib.append('GOBJECT')
	def addflags(flags):
		self.env.append_value('VALAFLAGS',flags)
	if self.profile:
		addflags('--profile=%s'%self.profile)
	if hasattr(self,'threading'):
		if self.profile=='gobject':
			if not'GTHREAD'in self.uselib:
				self.uselib.append('GTHREAD')
		else:
			Logs.warn("Profile %s means no threading support"%self.profile)
			self.threading=False
		if self.threading:
			addflags('--threading')
	valatask=self.valatask
	self.is_lib='cprogram'not in self.features
	if self.is_lib:
		addflags('--library=%s'%self.target)
		h_node=self.path.find_or_declare('%s.h'%self.target)
		valatask.outputs.append(h_node)
		addflags('--header=%s'%h_node.name)
		valatask.outputs.append(self.path.find_or_declare('%s.vapi'%self.target))
		if getattr(self,'gir',None):
			gir_node=self.path.find_or_declare('%s.gir'%self.gir)
			addflags('--gir=%s'%gir_node.name)
			valatask.outputs.append(gir_node)
	self.vala_target_glib=getattr(self,'vala_target_glib',getattr(Options.options,'vala_target_glib',None))
	if self.vala_target_glib:
		addflags('--target-glib=%s'%self.vala_target_glib)
	addflags(['--define=%s'%x for x in getattr(self,'vala_defines',[])])
	packages_private=Utils.to_list(getattr(self,'packages_private',[]))
	addflags(['--pkg=%s'%x for x in packages_private])
	def _get_api_version():
		api_version='1.0'
		if hasattr(Context.g_module,'API_VERSION'):
			version=Context.g_module.API_VERSION.split(".")
			if version[0]=="0":
				api_version="0."+version[1]
			else:
				api_version=version[0]+".0"
		return api_version
	self.includes=Utils.to_list(getattr(self,'includes',[]))
	self.uselib=self.to_list(getattr(self,'uselib',[]))
	valatask.install_path=getattr(self,'install_path','')
	valatask.vapi_path=getattr(self,'vapi_path','${DATAROOTDIR}/vala/vapi')
	valatask.pkg_name=getattr(self,'pkg_name',self.env['PACKAGE'])
	valatask.header_path=getattr(self,'header_path','${INCLUDEDIR}/%s-%s'%(valatask.pkg_name,_get_api_version()))
	valatask.install_binding=getattr(self,'install_binding',True)
	self.packages=packages=Utils.to_list(getattr(self,'packages',[]))
	self.vapi_dirs=vapi_dirs=Utils.to_list(getattr(self,'vapi_dirs',[]))
	includes=[]
	if hasattr(self,'use'):
		local_packages=Utils.to_list(self.use)[:]
		seen=[]
		while len(local_packages)>0:
			package=local_packages.pop()
			if package in seen:
				continue
			seen.append(package)
			try:
				package_obj=self.bld.get_tgen_by_name(package)
			except Errors.WafError:
				continue
			package_name=package_obj.target
			package_node=package_obj.path
			package_dir=package_node.path_from(self.path)
			for task in package_obj.tasks:
				for output in task.outputs:
					if output.name==package_name+".vapi":
						valatask.set_run_after(task)
						if package_name not in packages:
							packages.append(package_name)
						if package_dir not in vapi_dirs:
							vapi_dirs.append(package_dir)
						if package_dir not in includes:
							includes.append(package_dir)
			if hasattr(package_obj,'use'):
				lst=self.to_list(package_obj.use)
				lst.reverse()
				local_packages=[pkg for pkg in lst if pkg not in seen]+local_packages
	addflags(['--pkg=%s'%p for p in packages])
	for vapi_dir in vapi_dirs:
		v_node=self.path.find_dir(vapi_dir)
		if not v_node:
			Logs.warn('Unable to locate Vala API directory: %r'%vapi_dir)
		else:
			addflags('--vapidir=%s'%v_node.abspath())
			addflags('--vapidir=%s'%v_node.get_bld().abspath())
	self.dump_deps_node=None
	if self.is_lib and self.packages:
		self.dump_deps_node=self.path.find_or_declare('%s.deps'%self.target)
		valatask.outputs.append(self.dump_deps_node)
	self.includes.append(self.bld.srcnode.abspath())
	self.includes.append(self.bld.bldnode.abspath())
	for include in includes:
		try:
			self.includes.append(self.path.find_dir(include).abspath())
			self.includes.append(self.path.find_dir(include).get_bld().abspath())
		except AttributeError:
			Logs.warn("Unable to locate include directory: '%s'"%include)
	if self.is_lib and valatask.install_binding:
		headers_list=[o for o in valatask.outputs if o.suffix()==".h"]
		try:
			self.install_vheader.source=headers_list
		except AttributeError:
			self.install_vheader=self.bld.install_files(valatask.header_path,headers_list,self.env)
		vapi_list=[o for o in valatask.outputs if(o.suffix()in(".vapi",".deps"))]
		try:
			self.install_vapi.source=vapi_list
		except AttributeError:
			self.install_vapi=self.bld.install_files(valatask.vapi_path,vapi_list,self.env)
		gir_list=[o for o in valatask.outputs if o.suffix()=='.gir']
		try:
			self.install_gir.source=gir_list
		except AttributeError:
			self.install_gir=self.bld.install_files(getattr(self,'gir_path','${DATAROOTDIR}/gir-1.0'),gir_list,self.env)
@extension('.vala','.gs')
def vala_file(self,node):
	try:
		valatask=self.valatask
	except AttributeError:
		valatask=self.valatask=self.create_task('valac')
		self.init_vala_task()
	valatask.inputs.append(node)
	c_node=node.change_ext('.c')
	valatask.outputs.append(c_node)
	self.source.append(c_node)
@conf
def find_valac(self,valac_name,min_version):
	valac=self.find_program(valac_name,var='VALAC')
	try:
		output=self.cmd_and_log(valac+['--version'])
	except Exception:
		valac_version=None
	else:
		ver=re.search(r'\d+.\d+.\d+',output).group(0).split('.')
		valac_version=tuple([int(x)for x in ver])
	self.msg('Checking for %s version >= %r'%(valac_name,min_version),valac_version,valac_version and valac_version>=min_version)
	if valac and valac_version<min_version:
		self.fatal("%s version %r is too old, need >= %r"%(valac_name,valac_version,min_version))
	self.env['VALAC_VERSION']=valac_version
	return valac
@conf
def check_vala(self,min_version=(0,8,0),branch=None):
	if not branch:
		branch=min_version[:2]
	try:
		find_valac(self,'valac-%d.%d'%(branch[0],branch[1]),min_version)
	except self.errors.ConfigurationError:
		find_valac(self,'valac',min_version)
@conf
def check_vala_deps(self):
	if not self.env['HAVE_GOBJECT']:
		pkg_args={'package':'gobject-2.0','uselib_store':'GOBJECT','args':'--cflags --libs'}
		if getattr(Options.options,'vala_target_glib',None):
			pkg_args['atleast_version']=Options.options.vala_target_glib
		self.check_cfg(**pkg_args)
	if not self.env['HAVE_GTHREAD']:
		pkg_args={'package':'gthread-2.0','uselib_store':'GTHREAD','args':'--cflags --libs'}
		if getattr(Options.options,'vala_target_glib',None):
			pkg_args['atleast_version']=Options.options.vala_target_glib
		self.check_cfg(**pkg_args)
def configure(self):
	self.load('gnu_dirs')
	self.check_vala_deps()
	self.check_vala()
	self.env.VALAFLAGS=['-C','--quiet']
def options(opt):
	opt.load('gnu_dirs')
	valaopts=opt.add_option_group('Vala Compiler Options')
	valaopts.add_option('--vala-target-glib',default=None,dest='vala_target_glib',metavar='MAJOR.MINOR',help='Target version of glib for Vala GObject code generation')
