class CreateHoliday < ActiveRecord::Migration[6.1]
  def change
    create_table :holidays do |t|
      t.date :date
      t.string :name, charset: 'utf8mb4', collation: 'utf8mb4_unicode_ci'
      t.string :description, charset: 'utf8mb4', collation: 'utf8mb4_unicode_ci'
    end
  end
end

