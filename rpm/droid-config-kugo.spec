%global __requires_exclude_from ^/usr/libexec/droid-hybris/.*$
%global __provides_exclude_from ^/usr/libexec/droid-hybris/.*$


%define device kugo
%define rpm_device kugo
%define device_pretty Xperia X Compact

%define pixel_ratio 1.25

%include droid-config-common.inc
%define community_adaptation 1

%include droid-configs-device/droid-configs.inc
%include patterns/patterns-sailfish-device-adaptation-kugo.inc
%include patterns/patterns-sailfish-device-configuration-kugo.inc
