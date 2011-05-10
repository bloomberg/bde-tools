[% PROCESS svc_util.t -%]
<?xml version='1.0' encoding='UTF-8'?>
<Configuration xmlns='[% svc.targetNamespace %]'>

  <BasConfig>
    <TcpInterface>
      <Name>BASS.DYNAMIC.LOCALHOST</Name>
      <Mode>CONNECT</Mode>
      <Port>28663</Port>
      <Host>localhost</Host>
    </TcpInterface>

    <FastSendInterface>
      <Name>[% SERVICE %].FS</Name>
      <TaskNumber>[% svc.serviceId %]</TaskNumber>[% -%]
[%- IF svc.serviceId == 0 %]  <!-- TBD: specify task number -->[% END %]
      <Mode>SERVER</Mode>
    </FastSendInterface>

[% IF svc.WSDL -%]
[% PROCESS soapcfg.t -%]
[% INCLUDE SoapInterface -%]

[% INCLUDE SoapServiceDescription -%]

[% END -%]
    <ServiceInstance>
      <Name>[% SERVICE %]</Name>
      <Description>TBD: Provide Description</Description>
      <ServiceId>[% svc.serviceId %]</ServiceId>[% -%]
[%- IF svc.serviceId == 0 %]    <!-- TBD: specify task number -->[% END %]
      <Version>[% svc.serviceVersionMajor %].[% -%]
         [%- %][% svc.serviceVersionMinor %].0</Version>

      <ReplayJournal>
        <Filename>/bb/data/tmp/bas_replay.[% service %]</Filename>
        <EnableOnStartup>false</EnableOnStartup>
      </ReplayJournal>

      <CodecOptions>
        <XmlDecoderOptions>
          <SkipUnknownElements>false</SkipUnknownElements>
        </XmlDecoderOptions>
        <BerDecoderOptions>
          <SkipUnknownElements>false</SkipUnknownElements>
        </BerDecoderOptions>
      </CodecOptions>
    </ServiceInstance>

    <ServiceOfflineConfig>
      <OfflineConfig>
        <Name>[% service %]</Name>        <!-- Procmgr name from PWHO -->
        <LoggingConfig>
          <Filename>/bb/data/[% service %].log.%Y</Filename>
          <StdoutLoggingThreshold>2</StdoutLoggingThreshold>
          <VerbosityLevel>3</VerbosityLevel>
        </LoggingConfig>
        <ThreadPoolConfig>
          <NumThreads>1</NumThreads>
        </ThreadPoolConfig>
        <MetricsConfig>
          <PersistMetrics>false</PersistMetrics>
        </MetricsConfig>
      </OfflineConfig>

      <!-- ChannelPoolConfig/ --> <!-- Uncomment to configure TCP -->
    </ServiceOfflineConfig>

    <!-- Metrics aggregated across all service instances.
         All intervals are specified in seconds.
    -->
    <MetricsComponent>
      <Name>Offline</Name>
      <UpdateInterval>30</UpdateInterval>
    </MetricsComponent>
  </BasConfig>

  <!-- Specify additional application-level configuration elements here. -->

</Configuration>

<!-- \$Id\$ \$CSID\$ \$CCId\$ -->
<!-- vim:set syntax=xml tabstop=2 shiftwidth=2 expandtab: -->
