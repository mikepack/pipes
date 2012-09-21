# These are Resque jobs
module Writers
  class ContentWriter
    @queue = :content_writers
    def self.perform(locale)
      sleep 5
    end
  end

  class AnotherContentWriter
    @queue = :content_writers
    def self.perform(locale)
      sleep 5
    end
  end

  class UnregisteredStrategy
    @queue = :content_writers
    def self.perform; end
  end
end

module Publishers
  class Publisher
    @queue = :publishers
    def self.perform(locale)
      sleep 5
    end
  end
end

module Messengers
  class SMS
    def self.perform; end
  end
end

module Uploaders
  class Rsync
    def self.perform; end
  end
end

module Emailers
  class Email
    def self.perform; end
  end

  class AnotherEmail
    def self.perform; end
  end
end

module Notifiers
  class Twitter
    def self.perform; end
  end
end