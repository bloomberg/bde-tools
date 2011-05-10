[% PROCESS svc_util.t -%]
<?xml version='1.0' encoding='UTF-8'?>
<schema xmlns='http://www.w3.org/2001/XMLSchema'
        xmlns:bdem='http://bloomberg.com/schemas/bdem'
        xmlns:tns='[% svc.targetNamespace %]'
        targetNamespace='[% svc.targetNamespace %]' 
        bdem:serviceName='[% SERVICE %]'
        bdem:package='[% pkg %]'
        bdem:configuration='true'
        elementFormDefault='qualified'>

  <include schemaLocation='bascfg.xsd' bdem:inline='0'/>

  <complexType name='Configuration'>
    <sequence>
      <element name='BasConfig' type='tns:BasConfig'/>

    <!-- Specify additional application-level configuration elements here. -->

    </sequence>
  </complexType>

  <element name='Configuration' type='tns:Configuration'/>
</schema>

<!-- "\$Id\$ \$CSID\$ \$CCId\$" -->
