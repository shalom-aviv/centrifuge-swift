Pod::Spec.new do |s|
    s.name                  = 'SwiftCentrifugeExperiments'
    s.module_name           = 'SwiftCentrifugeExperiments'
    s.swift_version         = '5.0'
    s.version               = '0.8.1'

    s.homepage              = 'https://github.com/centrifugal/centrifuge-swift'
    s.summary               = 'Experiments with iOS Centrifuge client based on SwiftCentrifuge'

    s.author                = { 'Shalom Aviv' => 'shalom.aviv@proton.me' }
    s.license               = { :type => 'MIT', :file => 'LICENSE' }
    s.platforms             = { :ios => '12.0' }
    s.ios.deployment_target = '12.0'

    s.source_files          = 'Sources/SwiftCentrifugeExperiments/*/*.swift'
    s.source                = { :git => 'https://github.com/centrifugal/centrifuge-swift.git', :tag => s.version }

    s.dependency 'SwiftCentrifuge' '~> 0.8.1'
end