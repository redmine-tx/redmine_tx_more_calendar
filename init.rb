Redmine::Plugin.register :redmine_tx_more_calendar do
  name 'Redmine Tx More Calendar plugin'
  author 'KiHyun Kang'
  description 'This is a plugin for Redmine'
  version '0.0.1'
  url 'http://example.com/path/to/plugin'
  author_url 'http://example.com/about'

  settings :default => {
    'calendar_tracker' => [],
    'hide_query_form' => false
  }, :partial => 'settings/redmine_tx_more_calendar'
end

# Asset precompile 설정 추가
Rails.application.config.assets.precompile += %w( 
  toastui-calendar.min.js 
  toastui-calendar.min.css 
)

Rails.application.config.after_initialize do
  require_dependency File.expand_path('../lib/tx_more_calendar_helper', __FILE__)

  Redmine::Helpers::Calendar.send(:prepend, TxMoreCalendarHelper::TxCalendarHelperPatch)
end