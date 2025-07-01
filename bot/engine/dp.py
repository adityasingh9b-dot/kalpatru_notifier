import sqlite3

conn = sqlite3.connect("Jarvis.db")
cursor = conn.cursor()

query = "CREATE TABLE IF NOT EXISTS sys_command(id integer primary key, name VARCHAR(50), path VARCHAR(1000))"
cursor.execute(query)

query = "CREATE TABLE IF NOT EXISTS web_command(id integer primary key, name VARCHAR(50), path VARCHAR(1000))"
cursor.execute(query)

query = "INSERT INTO web_command VALUES(NULL, ?, ?)"
cursor.execute(query, ('invest', 'https://univest.in/user/trade/live/stocks?cacheClear=1750658600688'))
conn.commit()


