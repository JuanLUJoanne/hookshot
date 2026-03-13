# frozen_string_literal: true

module Hookshot
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true
  end
end
