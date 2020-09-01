require 'spec_helper'
require 'openssl'
require 'json'
require 'ruby_event_store/spec/mapper_lint'

module RubyEventStore
  module Mappers
    SomeEventWithoutPersonalInfo = Class.new(RubyEventStore::Event)
    SomeEventWithPersonalInfo = Class.new(RubyEventStore::Event) do
      def self.encryption_schema
        {
          personal_info: ->(data) { data.fetch(:user_id) }
        }
      end
    end

    RSpec.describe EncryptionMapper do
      let(:key_repository)  { InMemoryEncryptionKeyRepository.new }
      let(:metadata)        { {some_meta: 1} }
      let(:event_id)        { SecureRandom.uuid }
      let(:coder)           { Transformation::Encryption.new(key_repository) }

      def build_data(value = 'test@example.com')
        {personal_info: value, user_id: 123}
      end
      def domain_event(data = build_data)
        SomeEventWithPersonalInfo.new(data: data, metadata: metadata, event_id: event_id)
      end
      def encrypted_item(event = domain_event)
        coder.dump(Transformation::DomainEvent.new.dump(event))
      end
      subject { described_class.new(key_repository) }

      it_behaves_like :mapper, EncryptionMapper.new(InMemoryEncryptionKeyRepository.new), TimestampEnrichment.with_timestamp(SomeEventWithoutPersonalInfo.new)

      before(:each) {
        key = key_repository.create(123)
        allow(key).to receive(:random_iv).and_return('123456789012')
      }

      specify '#event_to_serialized_record returns YAML serialized record' do
        record = subject.event_to_serialized_record(domain_event)
        expect(record).to            be_a SerializedRecord
        expect(record.event_id).to   eq event_id
        expect(record.data).to       eq YAML.dump(encrypted_item.data)
        expect(record.metadata).to   eq YAML.dump(encrypted_item.metadata)
        expect(record.event_type).to eq "RubyEventStore::Mappers::SomeEventWithPersonalInfo"
      end

      specify '#serialized_record_to_event returns event instance' do
        record = SerializedRecord.new(
          event_id:   domain_event.event_id,
          data:       YAML.dump(encrypted_item.data),
          metadata:   YAML.dump(encrypted_item.metadata),
          event_type: SomeEventWithPersonalInfo.name
        )
        event = subject.serialized_record_to_event(record)
        expect(event).to                eq(domain_event)
        expect(event.metadata.to_h).to  eq(metadata)
      end

      specify 'make sure encryption & decryption do not tamper event data' do
        [
          false,
          true,
          123,
          'Any string value',
          123.45,
          nil,
        ].each do |value|
          source_event = domain_event(build_data(value))
          encrypted = encrypted_item(source_event)
          record = SerializedRecord.new(
            event_id:   source_event.event_id,
            data:       YAML.dump(encrypted.data),
            metadata:   YAML.dump(encrypted.metadata),
            event_type: SomeEventWithPersonalInfo.name
          )
          event = subject.serialized_record_to_event(record)
          expect(event).to                eq(source_event)
          expect(event.metadata.to_h).to  eq(metadata)
        end
      end

      context 'when key is forgotten' do
        subject { described_class.new(key_repository) }

        specify '#serialized_record_to_event returns event instance with forgotten data' do
          record = SerializedRecord.new(
            event_id:   domain_event.event_id,
            data:       YAML.dump(encrypted_item.data),
            metadata:   YAML.dump(encrypted_item.metadata),
            event_type: SomeEventWithPersonalInfo.name
          )
          key_repository.forget(123)
          event = subject.serialized_record_to_event(record)
          expected_event = SomeEventWithPersonalInfo.new(
            data: build_data.merge(personal_info: ForgottenData.new),
            metadata: metadata,
            event_id: event_id
          )
          expect(event).to                      eq(expected_event)
          expect(event.metadata.to_h).to        eq(metadata)
          expect(event.data[:personal_info]).to eq('FORGOTTEN_DATA')
        end

        specify '#serialized_record_to_event returns event instance with forgotten data when a new key is created' do
          record = SerializedRecord.new(
            event_id:   domain_event.event_id,
            data:       YAML.dump(encrypted_item.data),
            metadata:   YAML.dump(encrypted_item.metadata),
            event_type: SomeEventWithPersonalInfo.name
          )
          key_repository.forget(123)
          key_repository.create(123)
          event = subject.serialized_record_to_event(record)
          expected_event = SomeEventWithPersonalInfo.new(
            data: build_data.merge(personal_info: ForgottenData.new),
            metadata: metadata,
            event_id: event_id
          )
          expect(event).to                      eq(expected_event)
          expect(event.metadata.to_h).to        eq(metadata)
          expect(event.data[:personal_info]).to eq('FORGOTTEN_DATA')
        end
      end

      context 'when key is forgotten and has custom forgotten data text' do
        let(:forgotten_data) { ForgottenData.new('Key is forgotten') }
        subject { described_class.new(key_repository, forgotten_data: forgotten_data) }

        specify '#serialized_record_to_event returns event instance with forgotten data' do
          record = SerializedRecord.new(
            event_id:   domain_event.event_id,
            data:       YAML.dump(encrypted_item.data),
            metadata:   YAML.dump(encrypted_item.metadata),
            event_type: SomeEventWithPersonalInfo.name
          )
          key_repository.forget(123)
          event = subject.serialized_record_to_event(record)
          expected_event = SomeEventWithPersonalInfo.new(
            data: build_data.merge(personal_info: forgotten_data),
            metadata: metadata,
            event_id: event_id
          )
          expect(event).to                      eq(expected_event)
          expect(event.metadata.to_h).to        eq(metadata)
          expect(event.data[:personal_info]).to eq('Key is forgotten')
        end
      end

      context 'when ReverseYamlSerializer serializer is provided' do
        let(:coder) { Transformation::Encryption.new(key_repository, serializer: ReverseYamlSerializer) }
        subject { described_class.new(key_repository, serializer: ReverseYamlSerializer) }

        specify '#event_to_serialized_record returns serialized record' do
          record = subject.event_to_serialized_record(domain_event)
          expect(record).to            be_a SerializedRecord
          expect(record.event_id).to   eq event_id
          expect(record.data).to       eq ReverseYamlSerializer.dump(encrypted_item.data)
          expect(record.metadata).to   eq ReverseYamlSerializer.dump(encrypted_item.metadata)
          expect(record.event_type).to eq "RubyEventStore::Mappers::SomeEventWithPersonalInfo"
        end

        specify '#serialized_record_to_event returns event instance' do
          record = SerializedRecord.new(
            event_id:   domain_event.event_id,
            data:       ReverseYamlSerializer.dump(encrypted_item.data),
            metadata:   ReverseYamlSerializer.dump(encrypted_item.metadata),
            event_type: SomeEventWithPersonalInfo.name
          )
          event = subject.serialized_record_to_event(record)
          expect(event).to                eq(domain_event)
          expect(event.metadata.to_h).to  eq(domain_event.metadata.to_h)
        end
      end
    end
  end
end
