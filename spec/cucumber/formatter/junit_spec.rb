# frozen_string_literal: true

require 'spec_helper'
require 'cucumber/formatter/spec_helper'
require 'cucumber/formatter/junit'
require 'nokogiri'

module Cucumber
  module Formatter
    class TestDoubleJunitFormatter < ::Cucumber::Formatter::Junit
      attr_reader :written_files

      def initialize(config)
        super
        config.on_event :test_step_started, &method(:on_test_step_started)
      end

      def on_test_step_started(_event)
        Interceptor::Pipe.unwrap! :stdout
        @fake_io = $stdout = StringIO.new
        $stdout.sync = true
        @interceptedout = Interceptor::Pipe.wrap(:stdout)
      end

      def on_test_step_finished(event)
        super
        $stdout = STDOUT
        @fake_io.close
      end

      def write_file(feature_filename, data)
        @written_files ||= {}
        @written_files[feature_filename] = data
      end
    end

    describe Junit do
      extend SpecHelperDsl
      include SpecHelper

      context 'with --junit,fileattribute=true option' do
        before(:each) do
          allow(File).to receive(:directory?).and_return(true)
          @formatter = TestDoubleJunitFormatter.new(
            actual_runtime.configuration.with_options(
              out_stream: '',
              formats: [['junit', { 'fileattribute' => 'true' }]]
            )
          )
        end

        describe 'includes the file' do
          before(:each) do
            run_defined_feature
            @doc = Nokogiri.XML(@formatter.written_files.values.first)
          end

          define_steps do
            Given('a passing scenario') do
              Kernel.puts 'foo'
            end
          end

          define_feature <<~FEATURE
            Feature: One passing feature

              Scenario: Passing
                Given a passing scenario
          FEATURE

          it 'contains the file attribute' do
            expect(@doc.xpath('//testsuite/testcase/@file').first.value).to eq('spec.feature')
          end
        end
      end

      context 'with --junit,fileattribute=different option' do
        before(:each) do
          allow(File).to receive(:directory?).and_return(true)
          @formatter = TestDoubleJunitFormatter.new(
            actual_runtime.configuration.with_options(
              out_stream: '',
              formats: [['junit', { 'fileattribute' => 'different' }]]
            )
          )
        end

        describe 'includes the file' do
          before(:each) do
            run_defined_feature
            @doc = Nokogiri.XML(@formatter.written_files.values.first)
          end

          define_steps do
            Given('a passing scenario') do
              Kernel.puts 'foo'
            end
          end

          define_feature <<~FEATURE
            Feature: One passing feature

              Scenario: Passing
                Given a passing scenario
          FEATURE

          it 'does not contain the file attribute' do
            expect(@doc.xpath('//testsuite/testcase/@file')).to be_empty
          end
        end
      end

      context 'with --junit no fileattribute option' do
        before(:each) do
          allow(File).to receive(:directory?).and_return(true)
          @formatter = TestDoubleJunitFormatter.new(actual_runtime.configuration.with_options(out_stream: ''))
        end

        describe 'includes the file' do
          before(:each) do
            run_defined_feature
            @doc = Nokogiri.XML(@formatter.written_files.values.first)
          end

          define_steps do
            Given('a passing scenario') do
              Kernel.puts 'foo'
            end
          end

          define_feature <<~FEATURE
            Feature: One passing feature

              Scenario: Passing
                Given a passing scenario
          FEATURE

          it 'does not contain the file attribute' do
            expect(@doc.xpath('//testsuite/testcase/@file')).to be_empty
          end
        end
      end

      context 'with no options' do
        before(:each) do
          allow(File).to receive(:directory?).and_return(true)
          @formatter = TestDoubleJunitFormatter.new(actual_runtime.configuration.with_options(out_stream: ''))
        end

        describe 'is able to strip control chars from cdata' do
          before(:each) do
            run_defined_feature
            @doc = Nokogiri.XML(@formatter.written_files.values.first)
          end

          define_steps do
            Given('a passing ctrl scenario') do
              Kernel.puts "boo\b\cx\e\a\f boo "
            end
          end

          define_feature <<~FEATURE
            Feature: One passing scenario, one failing scenario

              Scenario: Passing
                Given a passing ctrl scenario
          FEATURE

          it { expect(@doc.xpath('//testsuite/testcase/system-out').first.content).to match(/\s+boo boo\s+/) }
        end

        describe 'a feature with no name' do
          define_feature <<~FEATURE
            Feature:
              Scenario: Passing
                Given a passing scenario
          FEATURE

          it 'raises an exception' do
            expect { run_defined_feature }.to raise_error(Junit::UnNamedFeatureError)
          end
        end

        describe 'given a single feature' do
          before(:each) do
            run_defined_feature
            @doc = Nokogiri.XML(@formatter.written_files.values.first)
          end

          describe 'with a single scenario' do
            define_feature <<~FEATURE
              Feature: One passing scenario, one failing scenario

                Scenario: Passing
                  Given a passing scenario
            FEATURE

            it { expect(@doc.to_s).to match(/One passing scenario, one failing scenario/) }

            it 'has not a root system-out node' do
              expect(@doc.xpath('//testsuite/system-out')).to be_empty
            end

            it 'has not a root system-err node' do
              expect(@doc.xpath('//testsuite/system-err')).to be_empty
            end

            it 'has a system-out node under <testcase/>' do
              expect(@doc.xpath('//testcase/system-out').length).to eq(1)
            end

            it 'has a system-err node under <testcase/>' do
              expect(@doc.xpath('//testcase/system-err').length).to eq(1)
            end
          end

          describe 'with a scenario in a subdirectory' do
            define_feature %(
              Feature: One passing scenario, one failing scenario

                Scenario: Passing
                  Given a passing scenario
            ), File.join('features', 'some', 'path', 'spec.feature')

            it 'writes the filename with absolute path' do
              expect(@formatter.written_files.keys.first).to eq(File.absolute_path('TEST-features-some-path-spec.xml'))
            end
          end

          describe 'with a scenario outline table' do
            define_steps do
              Given('{word}') {}
            end

            define_feature <<~FEATURE
              Feature: Eat things when hungry

                Scenario Outline: Eat variety of things
                  Given <things>
                  And stuff:
                    | foo |
                    | bar |

                Examples: Good
                  | things   |
                  | Cucumber |

                Examples: Evil
                  | things   |
                  | Burger   |
                  | Whisky   |
            FEATURE

            it { expect(@doc.to_s).to match(/Eat things when hungry/) }
            it { expect(@doc.to_s).to match(/Cucumber/) }
            it { expect(@doc.to_s).to match(/Burger/) }
            it { expect(@doc.to_s).to match(/Whisky/) }
            it { expect(@doc.to_s).not_to match(/Cake/) }
            it { expect(@doc.to_s).not_to match(/Good|Evil/) }
            it { expect(@doc.to_s).not_to match(/type="skipped"/) }
          end

          describe 'scenario with flaky test in junit report' do
            before(:each) do
              # The first run gets fired off by the spec suite, so we need two more:
              actual_runtime.visitor = Fanout.new([@formatter])
              receiver = Cucumber::Core::Test::Runner.new(event_bus)

              event_bus.gherkin_source_read(gherkin_doc.uri, gherkin_doc.body)

              # Second run
              compile [gherkin_doc], receiver, filters, event_bus
              event_bus.test_run_finished

              # Third
              compile [gherkin_doc], receiver, filters, event_bus
              event_bus.test_run_finished

              @doc = Nokogiri.XML(@formatter.written_files.values.first)
            end

            define_steps do
              Given('a flaky scenario') do
                if $current_run.nil?
                  $current_run = 1
                else
                  $current_run += 1
                end
                raise "flake-#{$current_run}" if $current_run != 3
              end
            end

            define_feature <<~FEATURE
              Feature: junit report with flaky test

                Scenario: flaky a test and junit report of the same
                  Given a flaky scenario
            FEATURE

            it { expect(@doc.to_s).to match(/flakes="2"/) }
          end

          describe 'scenario with skipped test in junit report' do
            define_feature <<~FEATURE
              Feature: junit report with skipped test

                Scenario Outline: skip a test and junit report of the same
                  Given a <skip> scenario

                Examples:
                  | skip   |
                  | undefined |
                  | still undefined  |
            FEATURE

            it { expect(@doc.to_s).to match(/skipped="2"/) }
          end

          describe 'with a regular data table scenario' do
            define_steps do
              Given(/the following items on a shortlist/) { |table| }
              When(/I go.*/) {}
              Then(/I should have visited at least/) { |table| }
            end

            define_feature <<~FEATURE
              Feature: Shortlist

                Scenario: Procure items
                  Given the following items on a shortlist:
                    | item    |
                    | milk    |
                    | cookies |
                  When I get some..
                  Then I'll eat 'em

            FEATURE
            # these type of tables shouldn't crash (or generate test cases)
            it { expect(@doc.to_s).not_to match(/milk/) }
            it { expect(@doc.to_s).not_to match(/cookies/) }
          end

          context 'with failing hooks' do
            describe 'with a failing before hook' do
              define_steps do
                Before do
                  raise 'Before hook failed'
                end
                Given('a passing step') do
                end
              end

              define_feature <<~FEATURE
                Feature: One passing scenario

                  Scenario: Passing
                    Given a passing step
              FEATURE

              it { expect(@doc.to_s).to match(/Before hook at spec\/cucumber\/formatter\/junit_spec.rb:(\d+)/) }
            end

            describe 'with a failing after hook' do
              define_steps do
                After do
                  raise 'After hook failed'
                end
                Given('a passing step') do
                end
              end
              define_feature <<~FEATURE
                Feature: One passing scenario

                  Scenario: Passing
                    Given a passing step
              FEATURE

              it { expect(@doc.to_s).to match(/After hook at spec\/cucumber\/formatter\/junit_spec.rb:(\d+)/) }
            end

            describe 'with a failing after step hook' do
              define_steps do
                AfterStep do
                  raise 'AfterStep hook failed'
                end
                Given('a passing step') do
                end
              end
              define_feature <<~FEATURE
                Feature: One passing scenario

                  Scenario: Passing
                    Given a passing step
              FEATURE

              it { expect(@doc.to_s).to match(/AfterStep hook at spec\/cucumber\/formatter\/junit_spec.rb:(\d+)/) }
            end

            describe 'with a failing around hook' do
              define_steps do
                Around do |_scenario, block|
                  block.call
                  raise 'Around hook failed'
                end
                Given('a passing step') do
                end
              end
              define_feature <<~FEATURE
                Feature: One passing scenario

                  Scenario: Passing
                    Given a passing step
              FEATURE

              it { expect(@doc.to_s).to match(/Around hook\n\nMessage:/) }
            end
          end
        end
      end

      context 'In --expand mode' do
        let(:runtime) { Runtime.new(expand: true) }

        before(:each) do
          allow(File).to receive(:directory?).and_return(true)
          @formatter = TestDoubleJunitFormatter.new(actual_runtime.configuration.with_options(out_stream: '', expand: true))
        end

        describe 'given a single feature' do
          before(:each) do
            run_defined_feature
            @doc = Nokogiri.XML(@formatter.written_files.values.first)
          end

          describe 'with a scenario outline table' do
            define_steps do
              Given('{word}') {}
            end

            define_feature <<~FEATURE
              Feature: Eat things when hungry

                Scenario Outline: Eat things
                  Given <things>
                  And stuff:
                    | foo |
                    | bar |

                Examples: Good
                  | things   |
                  | Cucumber |

                Examples: Evil
                  | things   |
                  | Burger   |
                  | Whisky   |
            FEATURE

            it { expect(@doc.to_s).to match(/Eat things when hungry/) }
            it { expect(@doc.to_s).to match(/Cucumber/) }
            it { expect(@doc.to_s).to match(/Whisky/) }
            it { expect(@doc.to_s).to match(/Burger/) }
            it { expect(@doc.to_s).not_to match(/Things/) }
            it { expect(@doc.to_s).not_to match(/Good|Evil/) }
            it { expect(@doc.to_s).not_to match(/type="skipped"/) }
          end
        end
      end
    end
  end
end
