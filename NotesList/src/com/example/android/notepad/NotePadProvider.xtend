package com.example.android.notepad

import android.R
import android.content.ClipDescription
import android.content.ContentProvider
import android.content.ContentResolver
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.UriMatcher
import android.content.res.AssetFileDescriptor
import android.content.res.Resources
import android.database.Cursor
import android.database.SQLException
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.database.sqlite.SQLiteQueryBuilder
import android.net.Uri
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.provider.LiveFolders
import android.test.ProviderTestCase2
import android.text.TextUtils
import android.util.Log
import java.io.FileNotFoundException
import java.io.FileOutputStream
import java.io.IOException
import java.io.OutputStreamWriter
import java.io.PrintWriter
import java.io.UnsupportedEncodingException
import android.content.ContentProvider.PipeDataWriter

/** 
 * Provides access to a database of notes. Each note has a title, the note
 * itself, a creation date and a modified data.
 */
class NotePadProvider extends ContentProvider implements PipeDataWriter<Cursor> {

	protected static val TAG = 'NotePadProvider'
	protected static val DATABASE_NAME = 'note_pad.db'
	protected static val DATABASE_VERSION = 2
	protected static val sNotesProjectionMap = #{
		NotePad._ID -> NotePad._ID, 
		NotePad.COLUMN_NAME_TITLE -> NotePad.COLUMN_NAME_TITLE, 
		NotePad.COLUMN_NAME_NOTE -> NotePad.COLUMN_NAME_NOTE, 
		NotePad.COLUMN_NAME_CREATE_DATE -> NotePad.COLUMN_NAME_CREATE_DATE, 
		NotePad.COLUMN_NAME_MODIFICATION_DATE -> NotePad.COLUMN_NAME_MODIFICATION_DATE
	}
   
	protected static var sLiveFolderProjectionMap = #{ 
		LiveFolders._ID -> NotePad._ID + ' AS ' + LiveFolders._ID, 
		LiveFolders.NAME -> NotePad.COLUMN_NAME_TITLE + ' AS ' + LiveFolders.NAME
	}

	protected static val READ_NOTE_PROJECTION = #[NotePad._ID, NotePad.COLUMN_NAME_NOTE, NotePad.COLUMN_NAME_TITLE]
	protected static val READ_NOTE_NOTE_INDEX = 1
	protected static val READ_NOTE_TITLE_INDEX = 2
	protected static val NOTES = 1
	protected static val NOTE_ID = 2
	protected static val LIVE_FOLDER_NOTES = 3
	protected static var UriMatcher sUriMatcher = new UriMatcher(UriMatcher.NO_MATCH) => [
		addURI(NotePad.AUTHORITY, 'notes', NOTES)
		addURI(NotePad.AUTHORITY, 'notes/#', NOTE_ID)
		addURI(NotePad.AUTHORITY, 'live_folders/notes', LIVE_FOLDER_NOTES)
	]

	var DatabaseHelper mOpenHelper

	/** 
	 * Initializes the provider by creating a new DatabaseHelper. onCreate() is called
	 * automatically when Android creates the provider in response to a resolver request from a
	 * client.
	 */
	override onCreate() {
		mOpenHelper = new DatabaseHelper(context)
		true
	}

	/** 
	 * This method is called when a client calls{@link ContentResolver#query(Uri,String[],String,String[],String)}.
	 * Queries the database and returns a cursor containing the results.
	 * @return A cursor containing the results of the query. The cursor exists but is empty if
	 * the query returns no results or an exception occurs.
	 * @throws IllegalArgumentException if the incoming URI pattern is invalid.
	 */
	override query(Uri uri, String[] projection, String selection, String[] selectionArgs, String sortOrder) {
		var qb = new SQLiteQueryBuilder()
		qb.tables = NotePad.TABLE_NAME
		switch (sUriMatcher.match(uri)) {
			case NOTES: {
				qb.projectionMap = sNotesProjectionMap
			}
			case NOTE_ID: {
				qb.projectionMap = sNotesProjectionMap
				qb.appendWhere(NotePad._ID + '=' + uri.pathSegments.get(NotePad.NOTE_ID_PATH_POSITION))
			}
			case LIVE_FOLDER_NOTES: {
				qb.projectionMap = sLiveFolderProjectionMap
			}
			default:
				throw new IllegalArgumentException('Unknown URI ' + uri)
		}
		var String orderBy
		if (TextUtils.isEmpty(sortOrder)) {
			orderBy = NotePad.DEFAULT_SORT_ORDER
		} else {
			orderBy = sortOrder
		}
		var db = mOpenHelper.readableDatabase
		var c = qb.query(db, projection, selection, selectionArgs, null, null, orderBy)
		c.setNotificationUri(context.contentResolver, uri)
		c
	}

	/** 
	 * This is called when a client calls {@link ContentResolver#getType(Uri)}.
	 * Returns the MIME data type of the URI given as a parameter.
	 * @param uri The URI whose MIME type is desired.
	 * @return The MIME type of the URI.
	 * @throws IllegalArgumentException if the incoming URI pattern is invalid.
	 */
	override getType(Uri uri) {
		switch (sUriMatcher.match(uri)) {
			case NOTES:
				return NotePad.CONTENT_TYPE
			case LIVE_FOLDER_NOTES:
				return NotePad.CONTENT_TYPE
			case NOTE_ID:
				return NotePad.CONTENT_ITEM_TYPE
			default:
				throw new IllegalArgumentException('Unknown URI ' + uri)
		}
	}

	static var NOTE_STREAM_TYPES = new ClipDescription(null, #[ClipDescription.MIMETYPE_TEXT_PLAIN])

	/** 
	 * Returns the types of available data streams.  URIs to specific notes are supported.
	 * The application can convert such a note to a plain text stream.
	 * @param uri the URI to analyze
	 * @param mimeTypeFilter The MIME type to check for. This method only returns a data stream
	 * type for MIME types that match the filter. Currently, only text/plain MIME types match.
	 * @return a data stream MIME type. Currently, only text/plan is returned.
	 * @throws IllegalArgumentException if the URI pattern doesn't match any supported patterns.
	 */
	override getStreamTypes(Uri uri, String mimeTypeFilter) {
		switch (sUriMatcher.match(uri)) {
			case NOTES:
				return null
			case LIVE_FOLDER_NOTES:
				return null
			case NOTE_ID:
				return NOTE_STREAM_TYPES.filterMimeTypes(mimeTypeFilter)
			default:
				throw new IllegalArgumentException('Unknown URI ' + uri)
		}
	}

	/** 
	 * Returns a stream of data for each supported stream type. This method does a query on the
	 * incoming URI, then uses{@link ContentProvider#openPipeHelper(Uri,String,Bundle,Object,PipeDataWriter)} to start another thread in which to convert the data into a stream.
	 * @param uri The URI pattern that points to the data stream
	 * @param mimeTypeFilter A String containing a MIME type. This method tries to get a stream of
	 * data with this MIME type.
	 * @param opts Additional options supplied by the caller.  Can be interpreted as
	 * desired by the content provider.
	 * @return AssetFileDescriptor A handle to the file.
	 * @throws FileNotFoundException if there is no file associated with the incoming URI.
	 */
	override openTypedAssetFile(Uri uri, String mimeTypeFilter, Bundle opts) throws FileNotFoundException {
		var mimeTypes = getStreamTypes(uri, mimeTypeFilter)
		if (mimeTypes !== null) {
			var c = query(uri, READ_NOTE_PROJECTION, null, null, null)
			if (c === null || !c.moveToFirst) {
				if (c !== null) {
					c.close
				}
				throw new FileNotFoundException('Unable to query ' + uri)
			}
			return new AssetFileDescriptor(openPipeHelper(uri, mimeTypes.get(0), opts, c, this), 0,
				AssetFileDescriptor.UNKNOWN_LENGTH)
		}
		super.openTypedAssetFile(uri, mimeTypeFilter, opts)
	}

	/** 
	 * Implementation of {@link android.content.ContentProvider.PipeDataWriter}to perform the actual work of converting the data in one of cursors to a
	 * stream of data for the client to read.
	 */
	override writeDataToPipe(ParcelFileDescriptor output, Uri uri, String mimeType, Bundle opts, Cursor c) {
		var fout = new FileOutputStream(output.fileDescriptor)
		var PrintWriter pw = null
		try {
			pw = new PrintWriter(new OutputStreamWriter(fout, 'UTF-8'))
			pw.println(c.getString(READ_NOTE_TITLE_INDEX))
			pw.println('')
			pw.println(c.getString(READ_NOTE_NOTE_INDEX))
		} catch (UnsupportedEncodingException e) {
			Log.w(TAG, 'Ooops', e)
		} finally {
			c.close
			if (pw !== null) {
				pw.flush
			}
			try {
				fout.close
			} catch (IOException e) {
			}
		}
	}

	/** 
	 * This is called when a client calls{@link ContentResolver#insert(Uri,ContentValues)}.
	 * Inserts a new row into the database. This method sets up default values for any
	 * columns that are not included in the incoming map.
	 * If rows were inserted, then listeners are notified of the change.
	 * @return The row ID of the inserted row.
	 * @throws SQLException if the insertion fails.
	 */
	override insert(Uri uri, ContentValues initialValues) {
		if (sUriMatcher.match(uri) !== NOTES) {
			throw new IllegalArgumentException('Unknown URI ' + uri)
		}
		var ContentValues values
		if (initialValues !== null) {
			values = new ContentValues(initialValues)
		} else {
			values = new ContentValues()
		}
		var now = Long.valueOf(System.currentTimeMillis)
		if (values.containsKey(NotePad.COLUMN_NAME_CREATE_DATE) === false) {
			values.put(NotePad.COLUMN_NAME_CREATE_DATE, now)
		}
		if (values.containsKey(NotePad.COLUMN_NAME_MODIFICATION_DATE) === false) {
			values.put(NotePad.COLUMN_NAME_MODIFICATION_DATE, now)
		}
		if (values.containsKey(NotePad.COLUMN_NAME_TITLE) === false) {
			var r = Resources.system
			values.put(NotePad.COLUMN_NAME_TITLE, r.getString(R.string.untitled))
		}
		if (values.containsKey(NotePad.COLUMN_NAME_NOTE) === false) {
			values.put(NotePad.COLUMN_NAME_NOTE, '')
		}
		var db = mOpenHelper.writableDatabase
		var rowId = db.insert(NotePad.TABLE_NAME, NotePad.COLUMN_NAME_NOTE, values)
		if (rowId > 0) {
			var noteUri = ContentUris.withAppendedId(NotePad.CONTENT_ID_URI_BASE, rowId)
			context.contentResolver.notifyChange(noteUri, null)
			return noteUri
		}
		throw new SQLException('Failed to insert row into ' + uri)
	}

	/** 
	 * This is called when a client calls{@link ContentResolver#delete(Uri,String,String[])}.
	 * Deletes records from the database. If the incoming URI matches the note ID URI pattern,
	 * this method deletes the one record specified by the ID in the URI. Otherwise, it deletes a
	 * a set of records. The record or records must also match the input selection criteria
	 * specified by where and whereArgs.
	 * If rows were deleted, then listeners are notified of the change.
	 * @return If a "where" clause is used, the number of rows affected is returned, otherwise
	 * 0 is returned. To delete all rows and get a row count, use "1" as the where clause.
	 * @throws IllegalArgumentException if the incoming URI pattern is invalid.
	 */
	override delete(Uri uri, String where, String[] whereArgs) {
		var db = mOpenHelper.writableDatabase
		var String finalWhere
		var int count
		switch (sUriMatcher.match(uri)) {
			case NOTES: {
				count = db.delete(NotePad.TABLE_NAME, where, whereArgs)
			}
			case NOTE_ID: {
				finalWhere = NotePad._ID + ' = ' + uri.pathSegments.get(NotePad.NOTE_ID_PATH_POSITION)
				if (where !== null) {
					finalWhere = finalWhere + ' AND ' + where
				}
				count = db.delete(NotePad.TABLE_NAME, finalWhere, whereArgs)
			}
			default:
				throw new IllegalArgumentException('Unknown URI ' + uri)
		}
		context.contentResolver.notifyChange(uri, null)
		count
	}

	/** 
	 * This is called when a client calls{@link ContentResolver#update(Uri,ContentValues,String,String[])}Updates records in the database. The column names specified by the keys in the values map
	 * are updated with new data specified by the values in the map. If the incoming URI matches the
	 * note ID URI pattern, then the method updates the one record specified by the ID in the URI
	 * otherwise, it updates a set of records. The record or records must match the input
	 * selection criteria specified by where and whereArgs.
	 * If rows were updated, then listeners are notified of the change.
	 * @param uri The URI pattern to match and update.
	 * @param values A map of column names (keys) and new values (values).
	 * @param where An SQL "WHERE" clause that selects records based on their column values. If this
	 * is null, then all records that match the URI pattern are selected.
	 * @param whereArgs An array of selection criteria. If the "where" param contains value
	 * placeholders ("?"), then each placeholder is replaced by the corresponding element in the
	 * array.
	 * @return The number of rows updated.
	 * @throws IllegalArgumentException if the incoming URI pattern is invalid.
	 */
	override update(Uri uri, ContentValues values, String where, String[] whereArgs) {
		var db = mOpenHelper.writableDatabase
		var int count
		var String finalWhere
		switch (sUriMatcher.match(uri)) {
			case NOTES:
				count = db.update(NotePad.TABLE_NAME, values, where, whereArgs)
			case NOTE_ID: {

				finalWhere = NotePad._ID + ' = ' + uri.pathSegments.get(NotePad.NOTE_ID_PATH_POSITION)
				if (where !== null) {
					finalWhere = finalWhere + ' AND ' + where
				}
				count = db.update(NotePad.TABLE_NAME, values, finalWhere, whereArgs)
			}
			default:
				throw new IllegalArgumentException('Unknown URI ' + uri)
		}
		context.contentResolver.notifyChange(uri, null)
		count
	}

	/** 
	 * A test package can call this to get a handle to the database underlying NotePadProvider,
	 * so it can insert test data into the database. The test case class is responsible for
	 * instantiating the provider in a test context {@link ProviderTestCase2} does
	 * this during the call to setUp()
	 * @return a handle to the database helper object for the provider's data.
	 */
	def getOpenHelperForTest() {
		mOpenHelper
	}
}

/** 
 * This class helps open, create, and upgrade the database file. Set to package visibility
 * for testing purposes.
 */
class DatabaseHelper extends SQLiteOpenHelper {
	new(Context context) {
		super(context, NotePadProvider.DATABASE_NAME, null, NotePadProvider.DATABASE_VERSION)
	}

	/** 
	 * Creates the underlying database with table name and column names taken from the
	 * NotePad class.
	 */
	override onCreate(SQLiteDatabase db) {
		db.execSQL(
			'CREATE TABLE ' + NotePad.TABLE_NAME + ' (' + NotePad._ID + ' INTEGER PRIMARY KEY,' +
				NotePad.COLUMN_NAME_TITLE + ' TEXT,' + NotePad.COLUMN_NAME_NOTE + ' TEXT,' +
				NotePad.COLUMN_NAME_CREATE_DATE + ' INTEGER,' + NotePad.COLUMN_NAME_MODIFICATION_DATE + ' INTEGER' +
				')')
	}

	/** 
	 * Demonstrates that the provider must consider what happens when the
	 * underlying datastore is changed. In this sample, the database is upgraded the database
	 * by destroying the existing data.
	 * A real application should upgrade the database in place.
	 */
	override onUpgrade(SQLiteDatabase db, int oldVersion, int newVersion) {
		Log.w(NotePadProvider.TAG,
			'Upgrading database from version ' + oldVersion + ' to ' + newVersion + ', which will destroy all old data')
		db.execSQL('DROP TABLE IF EXISTS notes')
		onCreate(db)
	}
}
