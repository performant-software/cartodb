module Carto
  class SamlService
    def initialize(organization)
      raise "organization can't be nil" unless organization

      @organization = organization
    end

    def enabled?
      carto_saml_configuration.present?
    end

    def authentication_request
      OneLogin::RubySaml::Authrequest.new.create(saml_settings)
    end

    # This only works for existing users
    def username(saml_response_param)
      get_user(saml_response_param).try(:username)
    end

    def get_user(saml_response_param, create_if_not_exist: false)
      saml_response = saml_response_from_saml_response_param(saml_response_param)
      email = email_from_saml_response(saml_response)

      fetch_user(email) || (create_user(email) if create_if_not_exist)
    end

    private

    def fetch_user(email)
      # Can't match the username because ADFS can only redirect to one endpoint.
      # So this just checks to see if we have a user with this email address.
      # We can log them in at that point since identity is confirmed by BCG's ADFS.
      ::User.filter("email = ?", email.strip.downcase).first
    end

    def create_user(email)
    end

    def saml_response_from_saml_response_param(saml_response_param)
      response = get_saml_response(saml_response_param)

      if response.is_valid?
        response
      else
        message = "SAML response not valid"
        debug_response(message, response)
        raise message
      end
    end

    def email_from_saml_response(saml_response)
      email = saml_response.attributes[email_attribute]

      if email.present?
        email
      else
        message = "SAML response lacks email"
        debug_response("SAML response lacks email", saml_response)
        raise message
      end
    end

    def debug_response(message, response)
      CartoDB::Logger.debug(message: message, response_settings: response.settings, response_options: response.options)
    end

    def get_saml_response(saml_response_param)
      OneLogin::RubySaml::Response.new(
        saml_response_param,
        settings: saml_settings,
        allowed_clock_drift: carto_saml_configuration[:allowed_clock_drift] || 3600
      )
    end

    def email_attribute
      carto_saml_configuration[:email_attribute] || 'name_id'
    end

    # Transforms an email address (e.g. firstname.lastname@example.com) into a string
    # which can serve as a subdomain.
    # firstname.lastname@example.com -> firstname-lastname
    # Replaces all non-allowable characters with
    # hyphens. This could potentially result in collisions between two specially-
    # constructed names (e.g. John Smith-Bob and Bob-John Smith).
    # We're ignoring this for now since this type of email is unlikely to come up.
    # This method is used by the SAML authentication framework to create appropriate
    #
    # TODO: this is not currently used because `username` gets it based on the email.
    # This will be either used or deleted on #11073
    def email_to_subdomain(email)
      email.strip.split('@')[0].gsub(/[^A-Za-z0-9-]/, '-').downcase
    end

    # Our SAML library expects object properties
    # Adapted from https://github.com/hryk/warden-saml-example/blob/master/application.rb
    def saml_settings(settings_hash = carto_saml_configuration)
      settings = OneLogin::RubySaml::Settings.new
      settings_hash.each do |k, v|
        method = "#{k}="
        settings.__send__(method, v) if settings.respond_to?(method)
      end
      settings
    end

    def carto_saml_configuration
      @organization.try(:auth_saml_configuration)
    end
  end
end
