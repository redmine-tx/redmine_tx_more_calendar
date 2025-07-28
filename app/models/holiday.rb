class Holiday < ActiveRecord::Base
  validates :date, presence: true, uniqueness: true
  validates :name, presence: true

  scope :by_year, ->(year) { where('EXTRACT(year FROM date) = ?', year) }
  scope :by_month, ->(year, month) { where('EXTRACT(year FROM date) = ? AND EXTRACT(month FROM date) = ?', year, month) }
  scope :ordered, -> { order(:date) }

  # 스레드 세이프를 위한 뮤텍스
  @@cache_mutex = Mutex.new
  
  # 캐시된 범위들 [{ start_date: Date, end_date: Date, holidays: Hash }]
  @@cached_ranges = []
  
  # 전체 캐시된 휴일 데이터 { date => { id: x, date: date, name: name } }
  @@cached_holidays = {}

  def self.for_date_range(start_date, end_date)
    start_date = start_date.to_date
    end_date = end_date.to_date
    
    # 최소한 앞으로 2달치 조회하도록 범위 확장
    extended_end_date = [end_date, start_date + 2.months].max
    
    @@cache_mutex.synchronize do
      # 확장된 범위로 캐시 확인/조회
      ensure_range_cached(start_date, extended_end_date)
      
      # 요청된 범위의 휴일만 필터링해서 반환 (nil 값 제외)
      @@cached_holidays.select { |date, value| date >= start_date && date <= end_date && value.present? }
    end
  end

  def self.holiday?(date)
    date = date.to_date
    
    @@cache_mutex.synchronize do
      # 해당 날짜가 캐시에 있는지 확인
      if @@cached_holidays.key?(date)
        return @@cached_holidays[date].present?
      end
      
      # 캐시에 없으면 해당 날짜부터 2달치 미리 조회
      start_date = date.beginning_of_month
      end_date = start_date + 2.months - 1.day
      ensure_range_cached(start_date, end_date)
      
      @@cached_holidays[date].present?
    end
  end

  def self.update()
    sync(Date.today.year - 1)
    sync(Date.today.year)
    sync(Date.today.year + 1)
  end

  def self.sync(year)
    # 캐시 키 생성
    cache_key = "holiday_data_#{year}"
    
    # 캐시에서 데이터 확인 (1주일 캐시)
    cached_data = Rails.cache.read(cache_key)
    
    if cached_data.nil?
      # 캐시에 데이터가 없으면 다운로드
      holiday_data = download_holiday_data(year)
      return [0, 0] if holiday_data.nil?
      
      # 다운로드 성공시 캐시에 저장 (1주일)
      Rails.cache.write(cache_key, holiday_data, expires_in: 1.week)
    else
      holiday_data = cached_data
    end
    
    total_count = 0
    new_count = 0
    
    holiday_data.each do |date_str, names|
      date = Date.parse(date_str)
      name = names.join(', ') # 여러 공휴일이 겹치는 경우 쉼표로 연결
      
      total_count += 1
      
      # 중복 체크 후 저장
      unless Holiday.exists?(date: date)
        Holiday.create!(date: date, name: name)
        new_count += 1
      end
    end
    
    [new_count, total_count]
  end

  private

  def self.download_holiday_data(year)
    require 'net/http'
    require 'json'
    
    # 공휴일 데이터 다운로드
    url = "https://raw.githubusercontent.com/DaeHyeoNi/holidays-kr/refs/heads/master/data/#{year}.json"
    uri = URI(url)
    
    begin
      response = Net::HTTP.get_response(uri)
      
      unless response.code == '200'
        raise "HTTP 요청 실패: #{response.code}"
      end
      
      JSON.parse(response.body)
    rescue => e
      Rails.logger.error "공휴일 데이터 다운로드 실패: #{e.message}"
      nil
    end
  end

  def to_s
    name
  end

  # 지정된 범위가 캐시에 있는지 확인하고, 없으면 DB에서 조회해서 캐시
  def self.ensure_range_cached(start_date, end_date)
    # 현재 요청 범위가 이미 캐시된 범위에 완전히 포함되는지 확인
    if fully_cached?(start_date, end_date)
      return
    end

    # 병합 가능한 범위들을 찾고 병합
    merged_range = merge_with_existing_ranges(start_date, end_date)
    
    # 병합된 범위에서 아직 캐시되지 않은 부분들을 찾아서 DB 조회
    uncached_ranges = find_uncached_ranges(merged_range[:start_date], merged_range[:end_date])
    
    # 캐시되지 않은 범위들을 DB에서 조회
    uncached_ranges.each do |range|
      fetch_and_cache_range(range[:start_date], range[:end_date])
    end
    
    # 캐시된 범위 정보 업데이트
    update_cached_ranges(merged_range[:start_date], merged_range[:end_date])
  end

  # 지정된 범위가 이미 캐시에 완전히 포함되어 있는지 확인
  def self.fully_cached?(start_date, end_date)
    @@cached_ranges.any? do |cached_range|
      cached_range[:start_date] <= start_date && cached_range[:end_date] >= end_date
    end
  end

  # 기존 캐시된 범위들과 병합 가능한 범위 찾기
  def self.merge_with_existing_ranges(start_date, end_date)
    merged_start = start_date
    merged_end = end_date
    
    @@cached_ranges.each do |cached_range|
      # 겹치거나 인접한 범위인지 확인 (하루 차이까지 인접으로 간주)
      if ranges_overlap_or_adjacent?(start_date, end_date, cached_range[:start_date], cached_range[:end_date])
        merged_start = [merged_start, cached_range[:start_date]].min
        merged_end = [merged_end, cached_range[:end_date]].max
      end
    end
    
    { start_date: merged_start, end_date: merged_end }
  end

  # 두 범위가 겹치거나 인접한지 확인
  def self.ranges_overlap_or_adjacent?(start1, end1, start2, end2)
    # 겹치거나 하루 차이로 인접한 경우
    !(end1 < start2 - 1.day || start1 > end2 + 1.day)
  end

  # 병합된 범위에서 아직 캐시되지 않은 부분들 찾기
  def self.find_uncached_ranges(start_date, end_date)
    uncached_ranges = []
    current_start = start_date
    
    # 캐시된 범위들을 시작일 순으로 정렬
    sorted_ranges = @@cached_ranges
                     .select { |r| ranges_overlap_or_adjacent?(start_date, end_date, r[:start_date], r[:end_date]) }
                     .sort_by { |r| r[:start_date] }
    
    sorted_ranges.each do |cached_range|
      # 현재 시작점이 캐시된 범위 시작보다 이전이면 갭이 있음
      if current_start < cached_range[:start_date]
        uncached_ranges << {
          start_date: current_start,
          end_date: [cached_range[:start_date] - 1.day, end_date].min
        }
      end
      
      # 다음 시작점을 캐시된 범위 다음으로 이동
      current_start = [cached_range[:end_date] + 1.day, current_start].max
    end
    
    # 마지막에 남은 범위가 있으면 추가
    if current_start <= end_date
      uncached_ranges << {
        start_date: current_start,
        end_date: end_date
      }
    end
    
    uncached_ranges
  end

  # DB에서 지정된 범위의 휴일을 조회해서 캐시에 저장
  def self.fetch_and_cache_range(start_date, end_date)
    holidays = where(date: start_date..end_date).ordered
    
    # 조회된 범위의 모든 날짜를 캐시에 저장 (휴일이 아닌 날은 nil로 저장)
    (start_date..end_date).each do |date|
      next if date.saturday? || date.sunday? # 주말은 캐시하지 않음 (선택사항)
      
      holiday = holidays.find { |h| h.date == date }
      @@cached_holidays[date] = holiday ? { id: holiday.id, date: holiday.date, name: holiday.name } : nil
    end
  end

  # 캐시된 범위 정보 업데이트
  def self.update_cached_ranges(start_date, end_date)
    # 병합된 범위와 겹치는 기존 범위들 제거
    @@cached_ranges.reject! do |cached_range|
      ranges_overlap_or_adjacent?(start_date, end_date, cached_range[:start_date], cached_range[:end_date])
    end
    
    # 새로운 병합된 범위 추가
    @@cached_ranges << {
      start_date: start_date,
      end_date: end_date,
      holidays: @@cached_holidays.select { |date, _| date >= start_date && date <= end_date }
    }
  end

  # 캐시 클리어 (테스트나 메모리 관리용)
  def self.clear_cache!
    @@cache_mutex.synchronize do
      @@cached_ranges.clear
      @@cached_holidays.clear
    end
  end

  # 캐시 상태 확인 (디버깅용)
  def self.cache_info
    @@cache_mutex.synchronize do
      {
        cached_ranges_count: @@cached_ranges.size,
        cached_holidays_count: @@cached_holidays.size,
        cached_ranges: @@cached_ranges.map { |r| "#{r[:start_date]} ~ #{r[:end_date]}" },
        memory_usage_estimate: "#{@@cached_holidays.size * 100} bytes" # 대략적인 추정
      }
    end
  end
end 