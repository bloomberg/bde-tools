[% PROCESS svc_util.t -%]
[% BLOCK SoapInterface -%]
    <SoapInterface>
      <Name>[% SERVICE %].SOAP</Name>
      <Description>SOAP interface for the [% SERVICE %] service</Description>
      <Port></Port>              <!-- TBD: specify TCP port -->
      <Backlog>20</Backlog>
      <ServiceMap>
        <ServiceInstance>[% SERVICE %]</ServiceInstance>
[% SET location = String.new(svc.service.port.address.location) -%]
[% SET URI = location.search('//.+?/')
           ? String.new(location.split('//.+?/').1).prepend('/')
           : location
-%]
        <ServiceURI>[% URI %]</ServiceURI>
      </ServiceMap>
      <!-- TBD: Add additional ServiceMap elements here -->
    </SoapInterface>
[% END -%]
[% BLOCK SoapServiceDescription -%]
    <SoapServiceDescription>
      <ServiceInstance>[% SERVICE %]</ServiceInstance>
      <PortName>[% svc.portType.0.name %]</PortName>
[% FOREACH operation = svc.portType.0.operation -%]
[% SET operationName = operation.name -%]
[% SET op = svc.binding.operation.$operationName -%]
      <ActionMap>
        <SoapAction>"[% op.operation.soapAction -%]"
 [%- %]</SoapAction>
        <OperationName>[% operation.name %]</OperationName>
        <RequestElementName>[% operation.input.requestElement -%]
  [%- %]</RequestElementName>
        <RequestElementNamespace>[% svc.targetNamespace -%]
  [%- %]</RequestElementNamespace>
        <ResponseElementName>[% operation.output.responseElement -%]
  [%- %]</ResponseElementName>
        <ResponseElementNamespace>[% svc.targetNamespace -%]
  [%- %]</ResponseElementNamespace>
      </ActionMap>
[% END -%]
    </SoapServiceDescription>
[% END -%]
