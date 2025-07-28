module TxMoreCalendarHelper

    def self.version_path(version)
        if Redmine::Plugin.installed?(:redmine_tx_milestone)
            "/projects/#{version.project.identifier}/milestone?view=milestone&version_id=#{version.id}"
        else
            "/versions/#{version.id}/edit"
        end
    end

    class CalendarEvent
        attr_accessor :id,:name, :start_date, :due_date, :version

        def initialize(name, start_date, due_date, version)
            @id = SecureRandom.hex(8)
            @name = name
            @start_date = start_date
            @due_date = due_date
            @version = version
        end
    end

    module TxCalendarHelperPatch
        extend ActiveSupport::Concern

        def events_on( date )
            @events.select { |event|
                ( event.start_date != nil && event.due_date != nil && event.start_date <= date && event.due_date >= date ) ||
                ( event.start_date == date && event.due_date.nil? ) ||
                ( event.start_date.nil? && event.due_date == date ) ||
                ( event.start_date != nil && event.due_date != nil && event.start_date < date && event.due_date > date )                
            }            
        end

        def all_events
            @events
        end
    end
end