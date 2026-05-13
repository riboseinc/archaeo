# frozen_string_literal: true

module Archaeo
  HealthReport = Struct.new(
    :total, :accessible, :missing, :errors, :details,
    keyword_init: true
  )

  HealthDetail = Struct.new(
    :snapshot, :status, :error,
    keyword_init: true
  )
end
