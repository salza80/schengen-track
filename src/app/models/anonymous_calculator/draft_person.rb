# frozen_string_literal: true

module AnonymousCalculator
  # Read-only stand-in for Person used until the first travel record is saved.
  # Person.new is deliberately avoided: instantiating an Active Record model on
  # a cold Lambda can load schema metadata and wake the database. This object
  # exposes only the small interface required by the empty calculator views and
  # services; AnonymousCalculator::FirstSave creates the real records later.
  class DraftPerson
    # Minimal null relation for calculations that normally consume the Person
    # visit and visa associations. It stays deliberately small so new callers
    # fail visibly instead of silently growing a second Active Record API.
    class EmptyCollection
      include Enumerable

      def each
        return enum_for(:each) unless block_given?
      end

      def all = self
      def where(*) = self
      def order(*) = self
      def not(*) = self
      def schengen = self
      def find_by_date(*) = self
      def find_visa_by_date(*) = self
      def to_a = []
      def count = 0
      def empty? = true
      def any? = false
      def exists? = false
      def first = nil
      def last = nil
    end

    attr_reader :first_name, :last_name, :nationality, :visits, :visas

    def initialize(nationality:, first_name: 'Guest', last_name: 'User')
      @first_name = first_name
      @last_name = last_name
      @nationality = nationality
      @visits = EmptyCollection.new.freeze
      @visas = EmptyCollection.new.freeze
    end

    def full_name
      [first_name, last_name].compact.join(' ')
    end

    def visa_required?
      nationality.visa_required == 'V'
    end

    def persisted?
      false
    end
  end
end
