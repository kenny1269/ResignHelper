# ResignHelper
ipa resign helper (only work with arm64 currently)

## Usage

Command line tool, build then use.

## Arguments

-i: path of ipa to resign

-s: sign identity of provisioning profile

-p: path of provisioning profile

-o: output path of resigned ipa (optional)

## Attention

Provisioning profile should contain a Wildcard App ID (*), or resign will failed
