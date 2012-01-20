require 'active_merchant'
require 'money'
include ActiveMerchant::Billing

class PaymentManager



###############################################################################################
###############################################################################################
############################[ General Credit Card Objects ]####################################
###############################################################################################
###############################################################################################


  # creates an ActiveMerchant credit card object from the given data
  def self.credit_card(type, number, exp_date, vcode, first_name='blank', last_name='blank')
    defaults = {
      :number => number,
      :month => exp_date.month,
      :year => exp_date.year,
      :first_name => first_name,
      :last_name => last_name,
      :verification_value => vcode,
      :type => type
    }
    CreditCard.new(defaults)
  end #end method self.credit_card
  
  
  
  # creates a hash of address data.  notable fields are:
  #
  # {
  #  :name => 'john smith', :address1 => '1234 some street', :city => 'Louisville', 
  #  :state => 'KY', :zip => '40202', :country => 'US'
  # }
  def self.billing_address(options = {})
    { 
      :first_name => '',
      :last_name  => '',
      :address1   => '',
      :address2   => '',
      :company    => '',
      :city       => '',
      :state      => '',
      :zip        => '',
      :country    => 'US',
      :phone      => '',
      :fax        => ''
    }.update(options)
  end #end method self.billing_address()
  
  
  
  #nested array of card types supported
  #by the application, for use w/ a drop down
  def self.supported_card_types
    [
      ["Visa", "visa"],
      ["Master Card", "master"],
      ["American Express", "american_express"],
      ["Discover", "discover"]
    ]
  end
  
  
###############################################################################################
###############################################################################################
#######[ Functions for working with credit cards, where info is on hand ]######################
###############################################################################################
###############################################################################################
  
  
  
  #reserve funds on a customer's credit card, but does not charge the card
  def self.authorize(amount, credit_card, options = {:order_id => 1, :billing_address => {}, :description => ""})
    unless credit_card.valid?
      return [nil, "Credit card is invalid: #{credit_card.errors.full_messages.join(", ")}"]
    end
    
    gateway = AuthorizeNetGateway.new(AUTH_NET)
    response = gateway.authorize(amount, credit_card, options)
    
    if response.success?
      authorization_id = response.authorization
      [authorization_id, response.message]
    else
      [nil, response.message]
    end
  end #end method self.authorize
  
  
  
  #method to capture funds from a previously authorized transaction
  def self.capture(amount, authorization_id)
    
    gateway = AuthorizeNetGateway.new(AUTH_NET)
    response = gateway.capture(amount, authorization_id)
    
    if response.success?
      transaction_id = response.authorization
      [transaction_id, response.message]
    else
      [nil, response.message]
    end
    
  end #end method self.capture
  


  # method to do a 1-off credit card charge. authorize then capture
  def self.purchase(amount, credit_card, options = {:order_id => 1, :billing_address => {}, :description => ""})
    unless credit_card.valid?
      return [nil, "Credit card is invalid: #{credit_card.errors.full_messages.join(", ")}"]
    end
    
    gateway = AuthorizeNetGateway.new(AUTH_NET)
    response = gateway.purchase(amount, credit_card, options)
    
    if response.success?
      transaction_id = response.authorization
      [transaction_id, response.message]
    else
      [nil, response.message]
    end
  end #end method self.purchase
  
  
  
  # method to charge a credit card $1.00 then if successful, immediatley void the charge.
  def self.verify_card_with_auth(credit_card, options = {:order_id => 1, :billing_address => {}, :description => "", :email => ""})
    
    unless credit_card.valid?
      return [nil, "Credit card is invalid: #{credit_card.errors.full_messages.join(", ")}"]
    end
    
    
    amount = "1.00".to_money
    gateway = AuthorizeNetGateway.new(AUTH_NET)
    response = gateway.authorize(amount, credit_card, options)
    
    #auth was successful, void it and return
    if response.success?
      
      authorization_id = response.authorization
      void_response = gateway.void(authorization_id)

      if void_response.success?
        #auth and void was success, return
        return [true, "Credit card successfully authorized and voided $1.00"]
      else
        #auth passed, but void failed
        return [false, "Credit Card Validation: #{void_response.message}"]
      end
      
    else
      #auth failed return message
      return [nil, "Credit Card Validation: #{response.message}"]
    end
    
  end #end method self.verify_card_with_auth()
  
  
  
  # method to void a transaction (authorization or uncleared transaction)
  def self.void(transaction_id)
    gateway = AuthorizeNetGateway.new(AUTH_NET)
    response = gateway.void(transaction_id)
    
    if response.success?
      [true, response.message]
    else
      [false, response.message]
    end
  end #end method self.void()
  
  
  
  # method to give a refund, the refund can't be more then the original purchase price.
  def self.refund(amount, transaction_id, options = {:card_number => '', :order_id => 0, :description => 'refund'})
    gateway = AuthorizeNetGateway.new(AUTH_NET)
    response = gateway.credit(amount, transaction_id, options)
    
    if response.success?
      [true, response.message]
    else
      [false, response.message]
    end
  end #end method self.refund(amount, transaction_id, options)



###############################################################################################
###############################################################################################
#######[ Functions for working with Auth.Net Recurring Billing Service ]#######################
###############################################################################################
###############################################################################################  
  
  
  
  # creates a hash of options required for Authorize.net recurring transactions
  def self.recurring_options(amount, credit_card, billing_address, description='Subscription', 
    start_date=nil, subscription_id=nil, trial_amount=nil, trial_occurrences=1, interval = 1, 
    interval_unit = :months, occurrences=6000)
    
    options = {
      :amount => amount,
      :credit_card => credit_card,
      :billing_address => billing_address,
      :subscription_name => description
    }
    
    options[:subscription_id] = subscription_id unless subscription_id.blank?
    
    unless start_date.blank?
      options[:duration] = {:start_date => start_date, :occurrences => occurrences}
      options[:interval] = {:length => interval, :unit => interval_unit}
    end
    
    unless trial_amount.blank?
      options[:trial] = {:amount => trial_amount, :occurrences => trial_occurrences}
    end
    
    
    options
    
  end #end method self.recurring_options()
  
  
  
  # method to add a recurring transaction to Authorize.net ARB
  def self.add_recurring(amount, credit_card, recurring_options)
    
    unless credit_card.valid?
      return [nil, "Credit card is invalid: #{credit_card.errors.full_messages.join(", ")}"]
    end
    
    
    gateway = AuthorizeNetGateway.new(AUTH_NET)
    response = gateway.recurring(amount, credit_card, recurring_options)
    
    if response.success?
      subscription_id = response.authorization
      [subscription_id, response.message]
    else
      [nil, response.message]
    end
  end #end method add_recurring(amount, credit_card, recurring_options)



  # method to update the amount of a already existing Authorize.net ARB transaction
  def self.update_recurring(options)
    
    gateway = AuthorizeNetGateway.new(AUTH_NET)
    response = gateway.update_recurring(options)
    [response.success?, response.message]
    
  end #end method update_recurring(subscription_id, new_amount)
  
  
  
  # method to cancel an Authorize.net ARB transaction
  def self.cancel_recurring(subscription_id)
    gateway = gateway = AuthorizeNetGateway.new(AUTH_NET)
    response = gateway.cancel_recurring(subscription_id)
    [response.success?, response.message]
  end #end method cancel_recurring(subscription_id)
  
    
    
###############################################################################################
###############################################################################################
#######################[ Functions for working with Auth.Net CIM Service]######################
###############################################################################################
###############################################################################################    
    
    
    
  #public function to create a customer profile for subsequent payments.
  def self.create_customer_profile(email, customer_id, profile_description, credit_card, billing_address)
    profile_result = PaymentManager.create_cim_profile(email, customer_id, profile_description)
    unless profile_result.first.nil?
      profile_id = profile_result.first
      payment_result = PaymentManager.create_cim_payment_profile(profile_id, credit_card, billing_address)
      unless payment_result.first.nil?
        return {:profile_id => profile_id, :payment_profile_id => payment_result.first}
      else
        return nil
      end
    else
      return nil
    end
  end #end method self.create_customer_profile(email, customer_id, description, credit_card, billing_address)
  
  
  
  #public function to charge a customer's existing profile
  def self.charge_customer_profile(amount, profile_id, payment_profile_id, charge_description)
    options = {
      :transaction => {
        :type => :auth_capture,
        :amount => amount,
        :customer_profile_id => profile_id,
        :customer_payment_profile_id => payment_profile_id,
        :order => {
          :description => charge_description
        }
      },
      :email_customer => false
    }
    
    gateway = AuthorizeNetCimGateway.new(AUTH_NET)
    response = gateway.create_customer_profile_transaction(options)
    
    if response.success?
      transaction_id = response.params["direct_response"]["transaction_id"]
      [transaction_id, response.message]
    else
      [nil, response.message]
    end
    
  end #end method self.charge_customer_profile
  
  
  
  #public function to delete a customer profile and all associated information
  def self.delete_customer_profile(pid)
    options = {
      :customer_profile_id => pid
    }
    
    gateway = AuthorizeNetCimGateway.new(AUTH_NET)
    response = gateway.delete_customer_profile(options)
    
    if response.success?
      [true, response.message]
    else
      [false, response.message]
    end
    
  end #end method self.delete_customer_profile

  
  
  #private function to create a customer profile
  def self.create_cim_profile(email, customer_id=nil, desc=nil)
    options = {
      :profile => {
        :email => email
      }
    }
    options[:profile][:merchant_customer_id] = customer_id unless customer_id.blank?
    options[:profile][:description] = desc unless desc.blank?
    
    gateway = AuthorizeNetCimGateway.new(AUTH_NET)
    response = gateway.create_customer_profile(options)
    
    if response.success?
      profile_id = response.authorization
      [profile_id, response.message]
    else
      [nil, response.message]
    end
    
  end #end method self.create_profile(email, customer_id=nil, desc=nil)
  
  
  
  #private function used to create a customer *payment* profile
  def self.create_cim_payment_profile(profile_id, credit_card, billing_address)
    payment_profile_options = {
      :customer_profile_id => profile_id,
      :payment_profile => {
        :payment => {
          :credit_card => credit_card
        },
        :bill_to => billing_address
      }
    }
    
    gateway = AuthorizeNetCimGateway.new(AUTH_NET)
    response = gateway.create_customer_payment_profile(payment_profile_options)
    
    if response.success?
      payment_profile_id = response.params["customer_payment_profile_id"]
      [payment_profile_id, response.message]
    else
      [nil, response.message]
    end
    
  end #end method self.create_cim_payment_profile()
  
  
  
  # public function to update a CIM customer profile
  def self.update_cim_profile(profile_id, email, customer_id=nil, desc=nil)
    gateway = AuthorizeNetCimGateway.new(AUTH_NET)
    get_response = gateway.get_customer_profile({:customer_profile_id => profile_id})
    
    #set the options from the get result
    options = {
      :profile => {
        :customer_profile_id => profile_id,
        :email => get_response.params["profile"]["email"],
        :merchant_customer_id => get_response.params["profile"]["merchant_customer_id"],
        :description => get_response.params["profile"]["description"]
      }
    }
    
    #now update the options with what we have from the args
    options[:profile][:email] = email
    options[:profile][:merchant_customer_id] = customer_id unless customer_id.blank?
    options[:profile][:description] = desc unless desc.blank?
    
    response = gateway.update_customer_profile(options)
    
    if response.success?
      [true, response.message]
    else
      [false, response.message]
    end
    
  end #end method self.update_cim_profile(profile_id, email, customer_id=nil, desc=nil)
  
  
  
  #public function to update a payment profile
  def self.update_cim_payment_profile(profile_id, payment_profile_id, credit_card=nil, billing_address=nil)
    gateway = AuthorizeNetCimGateway.new(AUTH_NET)
    get_response = gateway.get_customer_payment_profile({:customer_profile_id => profile_id, :customer_payment_profile_id => payment_profile_id})
    
    options = {
      :customer_profile_id => profile_id,
      :payment_profile => {
        :customer_payment_profile_id => payment_profile_id,
        :payment => {
        #  :credit_card => get_response.params["payment_profile"]["payment"]["credit_card"]
        },
        :bill_to => get_response.params["payment_profile"]["bill_to"]
      }
    }
    
    #now update the options with what we have from the args
    #options[:payment_profile][:payment] = {} unless credit_card.blank?
    options[:payment_profile][:payment][:credit_card] = credit_card unless credit_card.blank?
    options[:payment_profile][:bill_to] = billing_address unless billing_address.blank?
    
    response = gateway.update_customer_payment_profile(options)
    
    if response.success?
      [true, response.message]
    else
      [false, response.message]
    end
  end #end method self.update_cim_payment_profile()
  

end #end class