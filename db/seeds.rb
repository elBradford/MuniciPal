require "progressbar"
require "csv"

def announce(message)
  puts "\n\e[34;1m#{message}...\e[0m"
end



# This is data that we gathered manually from the Internet

COURTS_THAT_ARENT_IN_MUNICIPAL_COURT_LOCATIONS = [
  {name: "Bellerive", address: "7700 Natural Bridge Normandy", website: "http://www.courts.mo.gov/page.jsp?id=8707", zip_code: "63121", lat: -90.2908532, long: 38.6986447},
  {name: "Berkeley", address: "8425 Airport Road", website: "http://www.cityofberkeley.us/index.aspx?NID=124", zip_code: "63134", lat: -90.3305343, long: 38.7504723},
  {name: "Champ", address: nil, website: "https://en.wikipedia.org/wiki/Champ,_Missouri", zip_code: nil, lat: nil, long: nil},
  {name: "City of St. Louis", website: "http://www.stlcitycourt.org/frmHome.aspx", address: "1520 Market Street", zip_code: "63103", lat: -90.2032245, long: 38.6282597},
  {name: "Country Life Acres", address: "3 Hollenberg Ct.", zip_code: "63044", lat: 38.7531038, long: -90.4416799},
  {name: "Crystal Lake Park", address: "10555 Clayton Road", zip_code: "63131", website: "http://www.courts.mo.gov/page.jsp?id=9399", lat: -90.4121232, long: 38.6338913},
  {name: "Glen Echo Park", address: "7206 Henderson Avenue", zip_code: "63121", lat: -90.294752, long: 38.699572},
  {name: "Green Park", address: "11100 Mueller Rd., Suite 6", website: "http://www.stlouisco.com/YourGovernment/Municipalities/SouthCounty/GreenPark", zip_code: "63123", lat: -90.3455605, long: 38.5226969},
  {name: "Huntleigh", address: "600 Washington Ave, Fl 15", zip_code: "63101", website: "https://www.stlouisco.com/YourGovernment/Municipalities/MidCounty/Huntleigh" ,lat: -90.1898815, long: 38.6296495},
  {name: "Norwood Court", address: "250 North Boulden Avenue", zip_code: "65717", website: "http://www.courts.mo.gov/page.jsp?id=9715", lat: -92.4145246, long: 37.1088043},
  {name: "Twin Oaks", address: "1393 Big Bend Road, Suite F", zip_code: "63021", website: "http://www.vil.twin-oaks.mo.us/", lat: -90.4983795, long: 38.5694792},
  {name: "Westwood", address: "7700 Bonhomme Ave.", zip_code: "63105", website: "https://www.stlouisco.com/YourGovernment/Municipalities/WestCounty/Westwood", lat: -90.335175, long: 38.647037},
  {name: "Wilbur Park", address: "9036 Rosemary Ave", zip_code: "63123", website: "http://www.villageofwilburpark.com/", lat: -90.307501, long: 38.554451}
].freeze



# --------------------------------------------------------------------------- #
# Import Courts, info from the Websites spreadsheet, and geodata              #
# --------------------------------------------------------------------------- #

# TODO: This currently sets the database to a clean slate, which is great for
# development; but this code could be used to sync in new citations and violations
# from different courthouses nightly; and it would just have to be adapted to
# "upsert" data from the spreadsheets rather than replacing it.

Court.delete_all



announce "Importing MunicipalCourtLocations.csv..."
rows = CSV.read(Rails.root.join("db/MunicipalCourtLocations.csv"), headers: true)
pbar = ProgressBar.new("progress", rows.count)
rows.each do |row|
  municipality = row["Municipali"]

  # !NOTE: These actually have different courthouses, so it is
  # not right to merge these all into one "Unincorporated" Courthouse!
  # But we don't have a way of separating the geometry out into the
  # four quadrants; so we're going to converge them so that we can
  # show all the geometry for the demo.
  municipality = "Unincorporated" if municipality == "Unincorporated Central St. Louis County"
  if ["Unincorporated West St. Louis County", "Unincorporated North St. Louis County", "Unincorporated South St. Louis County"].member?(municipality)
    pbar.inc
    next
  end

  Court.create!(
    name: municipality,
    address: row["Address"],
    zip_code: row["Zip_Code"],
    lat: row[0], # something weird with the name of the column
    long: row["Y"])
  pbar.inc
end
pbar.finish



# Manually inserting some records
Court.create!(COURTS_THAT_ARENT_IN_MUNICIPAL_COURT_LOCATIONS)



announce "Importing MunicipalCourtWebsites.csv..."
rows = CSV.read(Rails.root.join("db/MunicipalCourtWebsites.csv"), headers: true)
unmatched_courts = []
pbar = ProgressBar.new("progress", rows.count)
rows.each do |row|
  next if row["Municipality"].nil?

  court = Court.find_by_name row["Municipality"]
  if court
    court.update_attributes!(
      municipal_website: row["Municipal Website"],
      website: row["Municipal Court Website"],
      phone_number: row["Court Clerk Phone Number Listed on Muni Site?"],
      online_payment_provider: row["Online Payment System Provider"])
  else
    unmatched_courts.push row["Municipality"]
  end
  pbar.inc
end
pbar.finish

if unmatched_courts.any?
  unmatched_courts = unmatched_courts.uniq.sort
  puts "\n\e[33mSkipping website data for #{unmatched_courts.count} courts that aren't in MunicipalCourtLocations.csv:"
  unmatched_courts.each do |name|
    puts "  #{name}"
  end
  print "\e[0m"
end

courts_without_website = Court.where(website: nil).pluck(:name).uniq.sort
if courts_without_website.any?
  puts "\n\e[34mThere are still #{courts_without_website.count} courts that we don't have a website for:"
  courts_without_website.each do |name|
    puts "  #{name}"
  end
  print "\e[0m"
end

courts_without_phone_number = Court.where(phone_number: nil).pluck(:name).uniq.sort
if courts_without_phone_number.any?
  puts "\n\e[34mThere are still #{courts_without_phone_number.count} courts that we don't have a phone number for:"
  courts_without_phone_number.each do |name|
    puts "  #{name}"
  end
  print "\e[0m"
end



announce "Importing courts.geojson..."
geometry = ActiveSupport::JSON.decode(File.read(Rails.root.join("db/courts.geojson")))["features"]
unmatched_courts = []
pbar = ProgressBar.new("progress", geometry.count)
geometry.each do |feature|
  court = Court.find_by_name feature["properties"]["court_name"]
  if court
    court.add_geometry! feature["geometry"]
  else
    unmatched_courts.push feature["properties"]["court_name"]
  end
  pbar.inc
end
pbar.finish

if unmatched_courts.any?
  unmatched_courts = unmatched_courts.uniq.sort
  puts "\n\e[33mSkipping geometry for #{unmatched_courts.count} courts that aren't in MunicipalCourtLocations.csv:"
  unmatched_courts.each do |name|
    puts "  #{name}"
  end
  print "\e[0m"
end

unplotted_courts = Court.where(geometry: nil).pluck(:name).uniq.sort
if unplotted_courts.any?
  puts "\n\e[33mThere are still #{unplotted_courts.count} courts that we don't have any geometry for:"
  unplotted_courts.each do |name|
    puts "  #{name}"
  end
  print "\e[0m"
end




# --------------------------------------------------------------------------- #
# Import Citations.csv                                                        #
# --------------------------------------------------------------------------- #

announce "Importing citations.csv..."
missing_citation_courts = []
Citation.delete_all
Person.delete_all
rows = CSV.read(Rails.root.join("db/citations.csv"), headers: true)
pbar = ProgressBar.new("progress", rows.count)
rows.each do |row|
  citation = Citation.new(row.to_h).tap(&:save!)
  missing_citation_courts.push citation.court_location if citation.court_location && !citation.court
  pbar.inc
end
pbar.finish

if missing_citation_courts.any?
  missing_citation_courts = missing_citation_courts.uniq.sort
  puts "\n\e[33mWe have citations for #{missing_citation_courts.count} courts that aren't in MunicipalCourtLocations.csv:"
  missing_citation_courts.each do |name|
    puts "  #{name}"
  end
  print "\e[0m"
end



# --------------------------------------------------------------------------- #
# Import Violations.csv                                                       #
# --------------------------------------------------------------------------- #

announce "Importing violations.csv..."
Violation.delete_all
rows = CSV.foreach(Rails.root.join("db/violations.csv"), headers: true)
pbar = ProgressBar.new("progress", rows.count)
rows.each do |row|
  attrs = row.to_h
  attrs["fine_amount"] = attrs["fine_amount"][1..-1].to_d if attrs["fine_amount"]
  attrs["court_cost"] = attrs["court_cost"][1..-1].to_d if attrs["court_cost"]
  Violation.create!(attrs)
  pbar.inc
end
pbar.finish



# --------------------------------------------------------------------------- #
# Tweak data for the demo                                                     #
# --------------------------------------------------------------------------- #

# Change Martin's name to Patricia
Person.where(drivers_license_number: "M718460675").update_all(first_name: "Patricia", last_name: "Rivera")

# Populate Ladue's court's real phone number
Court.where(name: "Ladue").update_all(phone_number: "(314) 993-3919")

# Fill in fake citation dates
Citation.where(citation_date: nil).update_all(citation_date: Date.new(2015, 7, 7))
