package com.dtnmesh.app.db

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase
import com.dtnmesh.app.model.BundleConverters
import com.dtnmesh.app.model.DTNBundle
import com.dtnmesh.app.model.ProphetEntry

@Database(
    entities = [DTNBundle::class, ProphetEntry::class],
    version = 2,
    exportSchema = false
)
@TypeConverters(BundleConverters::class)
abstract class AppDatabase : RoomDatabase() {
    abstract fun bundleDao(): BundleDao
    abstract fun prophetDao(): ProphetDao

    companion object {
        @Volatile private var INSTANCE: AppDatabase? = null

        private val MIGRATION_1_2 = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE bundles ADD COLUMN isEncrypted INTEGER NOT NULL DEFAULT 0")
                db.execSQL("ALTER TABLE bundles ADD COLUMN refBundleId TEXT")
                db.execSQL("""
                    CREATE TABLE IF NOT EXISTS prophet_entries (
                        localEid TEXT NOT NULL,
                        peerEid TEXT NOT NULL,
                        probability REAL NOT NULL DEFAULT 0,
                        lastUpdated INTEGER NOT NULL,
                        contactCount INTEGER NOT NULL DEFAULT 0,
                        PRIMARY KEY(localEid, peerEid)
                    )
                """.trimIndent())
            }
        }

        fun getInstance(context: Context): AppDatabase {
            return INSTANCE ?: synchronized(this) {
                Room.databaseBuilder(context.applicationContext, AppDatabase::class.java, "dtn_database")
                    .addMigrations(MIGRATION_1_2)
                    .fallbackToDestructiveMigration() // sólo en dev
                    .build()
                    .also { INSTANCE = it }
            }
        }
    }
}
