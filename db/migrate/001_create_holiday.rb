class CreateHoliday < ActiveRecord::Migration[6.1]
  def up
    unless table_exists?(:holidays)
      create_table :holidays do |t|
        t.date :date
        t.string :name, charset: 'utf8mb4', collation: 'utf8mb4_unicode_ci'
        t.string :description, charset: 'utf8mb4', collation: 'utf8mb4_unicode_ci'
      end
    end
  end

  def down
    drop_table :holidays if table_exists?(:holidays)
  end
end
