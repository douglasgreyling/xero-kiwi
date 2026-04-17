# frozen_string_literal: true

module XeroKiwi
  module Accounting
    # A Xero external link (social/web profile). Used by Organisation.
    #
    # See: https://developer.xero.com/documentation/api/accounting/types#externallinks
    class ExternalLink
      include Resource

      attribute :link_type, xero: "LinkType"
      attribute :url,       xero: "Url"
    end
  end
end
