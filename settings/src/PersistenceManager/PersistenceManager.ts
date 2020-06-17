import pg from 'pg'
import { internalServerError, okHttpCode } from '../Utilities/HttpCodes'
import APIInteraction from '../API/APIInteraction'
import APIMeasurableWorkDesiredBehavior from '../API/APIMeasurableWorkDesiredBehavior'
import APIOnboardCompany from '../API/APIOnboardCompany'
import APIOnboardUser from '../API/APIOnboardUser'
import APIQuadrantData from '../API/APIQuadrantData'
import APIQuadrantMetric from '../API/APIQuadrantMetric'
import APIQuadrantStats from '../API/APIQuadrantStats'
import APISalesProcessSkill from '../API/APISalesProcessSkill'
import APISkill from '../API/APISkill'
import APIStatus from '../API/APIStatus'
import APITeam from '../API/APITeam'
import APIXmetrics from '../API/APIXmetrics'
import APIYmetrics from '../API/APIYmetrics'
import CryptoFunctions from '../Crypto/CrytpoFunctions'
import DateHelper from '../Utilities/DateHelper'
import DbOutputValidator from '../Validation/DBOutputValidator'
import descriptors from './DatabaseDescriptors'
import errorCodes from '../ErrorCodes'
import General from '../Utilities/General'
import IActivity from '../Reporting/Interfaces/IActivity'
import IBehavior from '../DBTableInterfaces/IBehavior'
import IBehaviorRule from '../DBTableInterfaces/IBehaviorRule'
import ICompanyId from '../Onboarding/Interfaces/ICompanyId'
import ICompanyIdAndFrequency from '../DBTableInterfaces/ICompanyIdAndFrequency'
import ICoordDateNameId from '../DBTableInterfaces/ICoordDateNameId'
import ICoordinate from '../DBTableInterfaces/ICoordinate'
import ICurrentManagerInteractions from '../Handlers/Interfaces/ICurrentManagerInteractions'
import IDBTraining from '../DBTableInterfaces/IDBTraining'
import IDecodedAuthToken from '../Authorizer/IDecodedAuthToken'
import IDesiredBehavior from '../DBTableInterfaces/IDesiredBehavior'
import IFileMulter from '../Handlers/Interfaces/IFileMulter'
import IFormattedImpactReportData from '../Impact/InterfacesImpact/IFormattedImpactReportData'
import IImage from '../DBTableInterfaces/IImage'
import IImpactReport from '../DBTableInterfaces/IImpactReport'
import IInteraction from '../DBTableInterfaces/IInteraction'
import ILoggedInHistory from '../Reporting/Interfaces/ILoggedInHistory'
import ImpactReportDTO from '../Impact/ImpactReportDTO'
import IManagerList from '../Handlers/Interfaces/IManagerList'
import IMetric from '../MetricsAPI/Interfaces/IMetric'
import IMetricId from '../DBTableInterfaces/IMetricId'
import INameWithId from '../Onboarding/Interfaces/INameWithId'
import IOnboardBehavior from '../Onboarding/Interfaces/IOnboardBehavior'
import IPreviousManagerInteractions from '../Handlers/Interfaces/IPreviousManagerInteractions'
import IPersistenceManager from './IPersistenceManager'
import IQuadrantMetric from '../DBTableInterfaces/IQuadrantMetric'
import IRawDataForImpactReport from '../Impact/InterfacesImpact/IRawDataForImpactReport'
import IResult from '../DBTableInterfaces/IResult'
import IRevenueGoal from '../DBTableInterfaces/IRevenueGoal'
import IRevenueGoalInsert from '../Onboarding/Interfaces/IRevenueGoalInsert'
import IRevenueUnit from '../DBTableInterfaces/IRevenueUnit'
import IRole from '../DBTableInterfaces/IRole'
import IRoleIdName from '../Onboarding/Interfaces/IRoleIdName'
import IScorecardSkillsDTO from '../DBTableInterfaces/IScorecardSkillsDTO'
import ISFOAuthInfo from '../DBTableInterfaces/ISFOAuthInfo'
import ISkill from '../DBTableInterfaces/ISkill'
import ISkillPerformance from '../DBTableInterfaces/ISkillPerformance'
import ITerm from '../MetricsAPI/Interfaces/ITerm'
import ITraining from '../Handlers/Interfaces/ITraining'
import IUser from '../DBTableInterfaces/IUser'
import IUserAndManager from '../Onboarding/Interfaces/IUserAndManager'
import IUserIdCrmId from '../Quadrant/Interfaces/IUserIdCrmId'
import Logger from '../Logger/Logger'
import PersistImpactReportHelper from '../Impact/PersistImpactReportHelper'
import RecommendedAction from '../Handlers/SalesProcessAnalysis/Interfaces/RecommendedAction'
import SalesProcessAnalysisConfigRecord from '../DBTableInterfaces/SalesProcessAnalysisConfigRecord'
import StringManipulator from '../Utilities/StringManipulator'

const db = descriptors

class PersistenceManager implements IPersistenceManager {
  private databaseURI: string = process.env.DATABASE_URI

  public async addNewTraining(
    trainingContent: IFileMulter,
    contentExtension: string,
    trainingThumbnail: IFileMulter,
    thumbnailExtension: string,
    trainingName: string,
    trainingDescription: string,
    tags: string,
    userId: number,
    hasThumbnail: boolean
  ): Promise<ITraining> {
    const connection = this.openConnection()
    await this.beginTransactionWithConnection(connection)
    let thumbnailId = null

    if (hasThumbnail) {
      thumbnailId = await this.insertImageWithConnection(
        trainingThumbnail,
        thumbnailExtension,
        connection
      )
    }

    const trainingContentId = await this.insertDocumentWithConnection(
      trainingContent,
      contentExtension,
      connection
    )

    if ((hasThumbnail && !thumbnailId) || !trainingContentId) {
      Logger.info(
        'Rolling back -> Failed to insert training dependencies',
        'err'
      )
      return null
    }

    const trainingId = await this.insertTrainingWithConnection(
      trainingContentId,
      userId,
      trainingDescription,
      trainingName,
      tags,
      thumbnailId,
      connection
    )

    if (trainingId) {
      this.commitTransactionWithConnection(true, connection)
      Logger.info('Training successfully created', 'info')
      return {
        id: trainingId,
        name: trainingName,
        description: trainingDescription,
        tags: JSON.parse(tags),
        imageSrc: hasThumbnail
          ? `${trainingThumbnail.filename}.${thumbnailExtension}`
          : '',
        contentId: trainingContentId
      }
    } else {
      this.commitTransactionWithConnection(false, connection)
      Logger.info('Rolling back -> Training failed to insert', 'err')
      return null
    }
  }

  private insertImageWithConnection = async (
    imageFile: IFileMulter,
    fileExtension: string,
    connection: pg
  ): Promise<number> => {
    const { imagesTable } = db
    const insertStatement = `INSERT INTO ${imagesTable.tableName} (${imagesTable.name}, ${imagesTable.ext}, ${imagesTable.size}, ${imagesTable.type}) VALUES ($1, $2, $3, $4) RETURNING ${imagesTable.id};`
    const imageCreated = await this.paramQueryWithCustomConnection(
      insertStatement,
      [imageFile.filename, fileExtension, imageFile.size, imageFile.mimetype],
      connection
    )
    if (!imageCreated || !imageCreated[0]) {
      this.commitTransactionWithConnection(false, connection)
      Logger.info('Rolling back -> Image failed to insert', 'err')
      return null
    }
    return imageCreated[0][imagesTable.id]
  }

  private insertDocumentWithConnection = async (
    documentFile: IFileMulter,
    documentExtension: string,
    connection: pg
  ): Promise<number> => {
    const { documentsTable } = db
    const insertStatement = `INSERT INTO ${documentsTable.tableName} (${documentsTable.name}, ${documentsTable.ext}, ${documentsTable.size}, ${documentsTable.type}) VALUES ($1, $2, $3, $4) RETURNING ${documentsTable.id};`
    const documentCreated = await this.paramQueryWithCustomConnection(
      insertStatement,
      [
        documentFile.filename,
        documentExtension,
        documentFile.size,
        documentFile.mimetype
      ],
      connection
    )
    if (!documentCreated || !documentCreated[0]) {
      this.commitTransactionWithConnection(false, connection)
      Logger.info('Rolling back -> Document failed to insert', 'err')
      return null
    }
    return documentCreated[0][documentsTable.id]
  }

  public getTrainingsByUserId(userId: number): Promise<IDBTraining[]> {
    const { trainingsTable, userTable } = db
    const query = `SELECT * FROM ${trainingsTable.tableName} WHERE
    ${trainingsTable.createdById} IN (
    SELECT ${userTable.id} FROM ${userTable.tableName} WHERE
    ${userTable.companyId} IN (
    SELECT ${userTable.companyId} FROM ${userTable.tableName} WHERE ${userTable.id} = $1));`
    return this.paramQuery(query, [userId])
  }

  public async getImageName(imageId: number): Promise<string> {
    const { imagesTable } = db
    const query = `SELECT ${imagesTable.name}, ${imagesTable.ext} FROM ${imagesTable.tableName} WHERE id = $1;`
    const row = await this.paramQuery(query, [imageId])
    if (row && row[0]) {
      return `${row[0][imagesTable.name]}.${row[0][imagesTable.ext]}`
    }
    return null
  }

  private insertTrainingWithConnection = async (
    trainingContentId: number,
    userId: number,
    trainingDescription: string,
    trainingName: string,
    tags: string,
    thumbnailId: number,
    connection: pg
  ): Promise<any> => {
    const { trainingsTable } = db
    const trainingInsertStatement = `INSERT INTO ${trainingsTable.tableName} (${trainingsTable.contentId}, ${trainingsTable.createdById}, ${trainingsTable.description}, ${trainingsTable.name}, ${trainingsTable.tags}, ${trainingsTable.thumbnailId}, ${trainingsTable.updatedById}) VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING ${trainingsTable.id};`

    const res = await this.paramQueryWithCustomConnection(
      trainingInsertStatement,
      [
        trainingContentId,
        userId,
        trainingDescription,
        trainingName,
        tags,
        thumbnailId,
        userId
      ],
      connection
    )
    if (res && res[0]) {
      return res[0][trainingsTable.id]
    }
    return null
  }

  public getCRMIdsFromCompanyIds(
    companyIds: number[]
  ): Promise<{ crm_id: string; id: number }[]> {
    const { companyTable } = db
    const query = `SELECT ${companyTable.crmId} FROM ${
      companyTable.tableName
    } WHERE
    ${companyTable.id} IN ${this.parameterizeIdsForQuery(companyIds)};`
    return this.paramQuery(query, companyIds)
  }

  public async getMetricProfileIdByUserId(userId: number): Promise<number> {
    const { tableName, id, metricProfileId } = descriptors.userTable
    const query = `SELECT ${metricProfileId} FROM ${tableName} WHERE ${id} = $1;`
    const res = await this.paramQuery(query, [userId])
    if (res && res[0] && res[0][metricProfileId]) {
      return res[0][metricProfileId]
    }
    return null
  }

  public async persistSalesProcessAnalysisResultsData(
    userId: number,
    recommendedActions: RecommendedAction[],
    skills: APISkill[]
  ): Promise<void> {
    const connection = await this.openConnection()
    await this.beginTransactionWithConnection(connection)
    const {
      tableName,
      ownerId,
      winSkills,
      apiSkills
    } = descriptors.impactReportTable
    const deleteStatement = `DELETE FROM ${tableName} WHERE ${ownerId} = $1;`
    const deleteRes = await this.paramQueryWithCustomConnection(
      deleteStatement,
      [userId],
      connection
    )
    if (deleteRes) {
      const insertStatement = `INSERT INTO ${tableName}(${ownerId},${winSkills},${apiSkills}) VALUES ($1, $2, $3);`
      const res = await this.paramQueryWithCustomConnection(
        insertStatement,
        [userId, JSON.stringify(recommendedActions), JSON.stringify(skills)],
        connection
      )
      await this.commitTransactionWithConnection(!!res, connection)
      return
    }
    await this.commitTransactionWithConnection(false, connection)
  }

  public getSalesProcessAnalysisConfigurationByMetricIds(
    metricIds: number[]
  ): Promise<SalesProcessAnalysisConfigRecord[]> {
    const {
      tableName,
      metricId,
      relativeDifficulty
    } = descriptors.salesProcessAnalysisMetrics
    const query = `SELECT ${metricId}, ${relativeDifficulty} FROM ${tableName} WHERE ${metricId} IN ${this.parameterizeIdsForQuery(
      metricIds
    )};`
    return this.paramQuery(query, metricIds)
  }

  public async getSalesProcessPerformanceData(
    userId: number
  ): Promise<APISkill[]> {
    const { tableName, apiSkills, ownerId } = descriptors.impactReportTable
    const query = `SELECT ${apiSkills} FROM ${tableName} WHERE ${ownerId} = $1;`
    const res = await this.paramQuery(query, [userId])

    if (res && res[0] && res[0][apiSkills]) {
      if (PersistenceManager.isJsonString(res[0][apiSkills])) {
        return JSON.parse(res[0][apiSkills])
      }
    }
    return null
  }

  private static isJsonString(str) {
    try {
      JSON.parse(str)
    } catch (e) {
      return false
    }
    return true
  }

  public deleteSalesProcessAnalysisConfigurationByMetricIds(
    metricIds: number[]
  ): Promise<APIStatus> {
    const { tableName, metricId } = descriptors.salesProcessAnalysisMetrics
    const query = `DELETE FROM ${tableName} WHERE ${metricId} IN ${this.parameterizeIdsForQuery(
      metricIds
    )};`
    return this.paramQuery(query, metricIds)
  }

  public async upsertSalesProcessConfiguration(
    metricIds: number[],
    configuration: IMetricId[]
  ): Promise<void> {
    const connection = await this.openConnection()
    await this.beginTransactionWithConnection(connection)

    const { tableName, metricId } = descriptors.salesProcessAnalysisMetrics
    const deleteQuery = `DELETE FROM ${tableName} WHERE ${metricId} IN ${this.parameterizeIdsForQuery(
      metricIds
    )};`
    const deleteResult = await this.paramQueryWithCustomConnection(
      deleteQuery,
      metricIds,
      connection
    )

    if (deleteResult) {
      let insertQuery = `INSERT INTO ${tableName}(${metricId}) VALUES `
      for (let i = 0; i < configuration.length; i++) {
        insertQuery += `($${i + 1})`
        insertQuery += i === configuration.length - 1 ? ';' : ','
      }
      const insertResult = await this.paramQueryWithCustomConnection(
        insertQuery,
        configuration.map(metric => metric.metric_id),
        connection
      )

      await this.commitTransactionWithConnection(
        insertResult !== null,
        connection
      )
    } else {
      await this.commitTransactionWithConnection(false, connection)
    }
  }

  public async getCompanyStatusByCompanyId(id: number): Promise<object[]> {
    const { companyTable } = db
    const q = `SELECT ${companyTable.currentStatus} FROM ${companyTable.tableName} WHERE ${companyTable.id} = $1;`
    return this.paramQuery(q, [id])
  }

  public async getUserPasswordHashId(emailAddress: string): Promise<any> {
    const {
      accountType,
      companyId,
      email,
      id,
      isDeleted,
      name,
      passwordHash,
      tableName
    } = db.userTable
    const q = `SELECT ${accountType}, ${passwordHash}, ${id}, ${companyId}, ${name} FROM ${tableName} WHERE ${email} = $1
    AND ${isDeleted} = false;`
    const users = await this.paramQuery(q, [emailAddress])
    return users[0] || null
  }

  public paramQuery(query: string, values: any[]): Promise<any> {
    const connection = this.openConnection()
    return new Promise(resolve => {
      connection.query(query, values, (err, res) => {
        if (err) {
          const msg = `ERROR: PersistenceManager.ts -> paramQuery()\n Failed query: ${query}\n Values: ${values}\n err: ${err.message}\n`
          Logger.info(msg, 'err')
          resolve(null)
          connection.end()
        } else {
          const msg = `Successfully executed query: ${query}\n Values: ${values}`
          Logger.info(msg, 'info')
          connection.end()
          resolve(res.rows)
        }
      })
    })
  }

  public async getQueryNameOfSkillById(skillId: number): Promise<string> {
    const { query, id, tableName } = descriptors.skillsTable
    const result = await this.paramQuery(
      `SELECT ${query} FROM ${tableName} WHERE ${id} = $1;`,
      [skillId]
    )
    if (result && result[0]) {
      const queryObject = JSON.parse(result[0][query])
      if (queryObject && queryObject['queryName']) {
        return queryObject['queryName']
      }
    }
    return null
  }

  /* This needs to of return type any
   *  This method accepts a query string and will return what is requested by the query string.
   *  The caller of this method should specify what the return type is
   */
  public paramQueryWithCustomConnection(
    query: string,
    values: any[],
    connection: pg
  ): Promise<any> {
    return new Promise(resolve => {
      connection.query(query, values, (err, res) => {
        if (err) {
          const msg = `ERROR: PersistenceManager.ts -> paramQuery()\n Failed query: ${query}\n \n Values: ${values}\n err: ${err.message}\n`
          Logger.info(msg, 'err')
          resolve(null)
        } else {
          const msg = `Successfully executed query: ${query}\n Values: ${values}`
          Logger.info(msg, 'info')
          if (DbOutputValidator.isValidOutput(JSON.stringify(res.rows))) {
            resolve(res.rows)
          } else {
            const msgTwo = `Hazardous char(s) found in ${JSON.stringify(
              res.rows
            )}\n Query: ${query}\n`
            Logger.info(msgTwo, 'info')
            resolve(null)
          }
        }
      })
    })
  }

  public async beginTransactionWithConnection(connection: pg): Promise<void> {
    connection.query('BEGIN;', err => {
      if (err) {
        const msg = `ERROR: PersistenceManager.ts -> beginTransactionWithConnection()\n err: ${err.message}\n`
        Logger.info(msg, 'err')
      }
    })
  }

  public async commitTransactionWithConnection(
    commit: boolean,
    connection: pg
  ): Promise<void> {
    const msg = `commit transaction... commit: ${commit}`
    Logger.info(msg, 'info')
    if (commit) {
      await connection.query('COMMIT;', err => {
        if (err) {
          const msgTwo = `ERROR: PersistenceManager.ts -> commitTransactionWithConnection() -> COMMIT\n err: ${err.message}\n`
          Logger.info(msgTwo, 'err')
        }
        connection.end()
      })
    } else {
      await connection.query('ROLLBACK;', err => {
        if (err) {
          const msgTwo = `ERROR: PersistenceManager.ts -> commitTransactionWithConnection() -> ROLLBACK\n err: ${err.message}\n`
          Logger.info(msgTwo, 'err')
        }
        connection.end()
      })
    }
  }

  public async createCompanyAccount(
    companyName: string,
    connection: pg
  ): Promise<ICompanyId[]> {
    const { companyTable } = db
    const q = `INSERT INTO ${companyTable.tableName} (${
      companyTable.companyName
    }, 
    ${companyTable.currentStatus}, ${companyTable.crmId}) VALUES 
    ($1, 'onboard', '${companyName}onboarding-no-crm-id-info${StringManipulator.randomString()})
    RETURNING ${companyTable.id};`
    return this.paramQueryWithCustomConnection(q, [companyName], connection)
  }

  public async createUserAccount(
    fullName: string,
    email: string,
    password: string,
    companyId: number,
    connection: pg
  ): Promise<object[]> {
    const { userTable } = db
    const q = `INSERT INTO ${userTable.tableName} (${userTable.name}, ${userTable.role}, ${userTable.companyId}, 
    ${userTable.crmID}, ${userTable.email}, ${userTable.passwordHash}) VALUES 
    ($1, 'unknown-role', $2, 'unknown-crm-id', $3, $4);`
    return this.paramQueryWithCustomConnection(
      q,
      [fullName, companyId, email, password],
      connection
    )
  }

  public async emailExists(email: string): Promise<any> {
    const user = await this.query(
      `SELECT ${db.userTable.name}, ${db.userTable.id} FROM ${db.userTable.tableName} WHERE ${db.userTable.email} = '${email}';`
    )
    return user.length > 0 ? user[0] : null
  }

  private async executeCommit(
    commit: boolean,
    query: string,
    connection: pg.Client
  ): Promise<boolean> {
    const msg = `execute commit - commit: ${commit} QUERY: ${query}`
    Logger.info(msg, 'info')
    try {
      return this.queryWithConnection(query, connection)
    } catch (e) {
      const msgTwo = `ERROR: PersistenceManager.ts -> executeCommit()\n err: ${e.message}\n`
      Logger.info(msgTwo, 'err')
      return false
    }
  }

  public async getCompanyIdAndFrequencyFromCRMid(
    crmId: string
  ): Promise<ICompanyIdAndFrequency> {
    const res: ICompanyIdAndFrequency[] = await this.paramQuery(
      `SELECT ${db.companyTable.id}, ${db.companyTable.frequency} FROM ${db.companyTable.tableName} WHERE ${db.companyTable.crmId} = $1 LIMIT 1;`,
      [crmId]
    )
    if (res !== null && res[0]) {
      return res[0]
    }
    return null
  }

  public async getCompanyIdFromCrmId(crmID: string): Promise<number> {
    const { id, tableName, crmId } = db.companyTable
    const res: any[] = await this.paramQuery(
      `SELECT ${id} FROM ${tableName} WHERE ${crmId} = $1 LIMIT 1;`,
      [crmID]
    )
    if (res !== null && res.length > 0) {
      return res[0][db.companyTable.id]
    }
    return null
  }

  public async isAdmin(userId: number): Promise<boolean> {
    const { userTable } = db
    const q = `SELECT ${userTable.accountType} FROM ${userTable.tableName} WHERE 
    ${userTable.id} = $1 AND ${userTable.isDeleted} = false;`

    const res = await this.paramQuery(q, [userId])

    if (res[0]) {
      return res[0][userTable.accountType].toLowerCase().includes('admin')
    }
    return false
  }

  public async getImageAWSKey(
    userId: number,
    thumbnailId: number
  ): Promise<string> {
    if (await this.isImageFromUsersCompany(userId, thumbnailId)) {
      const { imagesTable } = db
      const query = `SELECT ${imagesTable.name}, ${imagesTable.ext} FROM 
      ${imagesTable.tableName} WHERE ${imagesTable.id} = $1;`

      const result = await this.paramQuery(query, [thumbnailId])

      if (result && result[0]) {
        const name = result[0][imagesTable.name]
        const ext = result[0][imagesTable.ext]
        return `${name}.${ext}`
      }
    }
    return null
  }

  private async isImageFromUsersCompany(
    userId: number,
    imageId: number
  ): Promise<boolean> {
    const { imagesTable, trainingsTable, userTable } = db
    const usersCompanyId: number = await this.getCompanyIdFromUserId(userId)
    const query = `SELECT COUNT(${imagesTable.id}) FROM ${imagesTable.tableName} WHERE ${imagesTable.id} = $1 AND ${imagesTable.id} IN (SELECT ${trainingsTable.thumbnailId} FROM ${trainingsTable.tableName} WHERE ${trainingsTable.createdById} IN (SELECT ${userTable.id} FROM ${userTable.tableName} WHERE ${userTable.companyId} = $2));`
    const res = await this.paramQuery(query, [imageId, usersCompanyId])
    return !!res && !!res[0] && res[0]['count'] === '1'
  }

  public async getDocumentAWSKey(
    userId: number,
    contentId: number
  ): Promise<string> {
    if (await this.isDocumentFromUsersCompany(userId, contentId)) {
      const { documentsTable } = db
      const query = `SELECT ${documentsTable.name}, ${documentsTable.ext} FROM ${documentsTable.tableName} WHERE ${documentsTable.id} = $1;`

      const result = await this.paramQuery(query, [contentId])

      if (result && result[0]) {
        const name = result[0][documentsTable.name]
        const ext = result[0][documentsTable.ext]
        return `${name}.${ext}`
      }
    }
    return null
  }

  private async isDocumentFromUsersCompany(
    userId: number,
    contentId: number
  ): Promise<boolean> {
    const { documentsTable, trainingsTable, userTable } = db
    const usersCompanyId: number = await this.getCompanyIdFromUserId(userId)
    const query = `SELECT COUNT(${documentsTable.id}) FROM 
    ${documentsTable.tableName} WHERE ${documentsTable.id} = $1 AND 
    ${documentsTable.id} IN (SELECT ${trainingsTable.contentId} FROM 
    ${trainingsTable.tableName} WHERE ${trainingsTable.createdById} IN 
    (SELECT ${userTable.id} FROM ${userTable.tableName} WHERE 
    ${userTable.companyId} = $2));`

    const res = await this.paramQuery(query, [contentId, usersCompanyId])
    return !!res && !!res[0] && res[0]['count'] === '1'
  }

  public async getImpactReportsByUserId(
    userId: number
  ): Promise<IImpactReport[]> {
    const { impactReportTable, userTable, coordinatesTable } = db
    const q = `SELECT * FROM ${impactReportTable.tableName} WHERE 
    ${impactReportTable.ownerId} IN (SELECT ${userTable.id} FROM 
    ${userTable.tableName} WHERE ${userTable.isDeleted} = false
    AND ${userTable.companyId} IN (SELECT ${userTable.companyId}
    FROM ${userTable.tableName} WHERE ${userTable.id} = $1)) 
    AND ${impactReportTable.ownerId} 
    IN (SELECT ${coordinatesTable.ownerId} FROM ${coordinatesTable.tableName});`

    return this.paramQuery(q, [userId])
  }

  public async getCRMKeyByOrgID(orgID: string): Promise<string> {
    const { companyTable } = db
    const query = `SELECT ${companyTable.crmKey} FROM 
    ${companyTable.tableName} WHERE ${companyTable.crmId} = $1 LIMIT 1;`

    const res: any[] = await this.paramQuery(query, [orgID])

    if (res.length < 1) {
      const msg = `ERROR: PersistenceManager.ts -> getCRMKeyByOrgID() - This Organization Identifier is not in our Database: '${orgID}\n`
      Logger.info(msg, 'err')
      return null
    }
    return res[0]
  }

  public async getCompanyFrequencyByUserId(userId: number): Promise<string> {
    const { companyTable, userTable } = db
    const q = `SELECT ${companyTable.frequency} FROM ${companyTable.tableName}
     WHERE ${companyTable.id} IN 
    (SELECT ${userTable.companyId} FROM ${userTable.tableName} WHERE 
    ${userTable.id} = $1 AND ${userTable.isDeleted} = false);`

    return this.paramQuery(q, [userId])
  }

  public async getCoordinatesLastComputedDate(userId: number): Promise<string> {
    const { lastComputedDate, tableName, ownerId } = db.coordinatesTable
    const query = `SELECT to_char(${lastComputedDate}, 'YYYY-MM-DD') FROM ${tableName} 
    WHERE ${ownerId} = $1 ORDER BY ${lastComputedDate} DESC LIMIT 1;`

    const res = await this.paramQuery(query, [userId])
    return res && res[0] && res[0]['to_char'] ? res[0]['to_char'] : null
  }

  public async getCompanyTagsByUserId(userId: number): Promise<object[]> {
    const { userTable, rolesTable, skillsTable, desiredBehaviorsTable } = db
    const companyIdSubQuery = `SELECT ${userTable.companyId} FROM
    ${userTable.tableName} WHERE ${userTable.id} = $1`

    const userRolesQuery = `SELECT DISTINCT ${userTable.role} FROM
    ${userTable.tableName} WHERE ${userTable.companyId} IN (${companyIdSubQuery})
    AND ${userTable.role} != 'db-admin';`

    const rolesNameQuery = `SELECT DISTINCT ${rolesTable.name} FROM
     ${rolesTable.tableName} WHERE ${rolesTable.companyId} IN (${companyIdSubQuery});`

    const skillQuery = `SELECT DISTINCT ${skillsTable.userFacingName} FROM
    ${skillsTable.tableName} WHERE ${skillsTable.companyId} IN (${companyIdSubQuery});`

    const behaviorsQuery = `SELECT DISTINCT ${desiredBehaviorsTable.name} FROM
    ${desiredBehaviorsTable.tableName} WHERE ${desiredBehaviorsTable.companyId} IN (${companyIdSubQuery});`

    const userRoles: string[] = await this.paramQuery(userRolesQuery, [userId])
    const roleNames: string[] = await this.paramQuery(rolesNameQuery, [userId])
    const skillNames: string[] = await this.paramQuery(skillQuery, [userId])
    const behaviorNames: string[] = await this.paramQuery(behaviorsQuery, [
      userId
    ])
    return []
      .concat(userRoles)
      .concat(roleNames)
      .concat(skillNames)
      .concat(behaviorNames)
      .filter(tag => tag !== null)
  }

  public async getRolesByCompanyId(
    id: number,
    columns?: string[]
  ): Promise<IRole[]> {
    const { rolesTable } = db

    const query = `SELECT ${this.includeColumns(columns, rolesTable)} FROM 
    ${rolesTable.tableName} WHERE ${rolesTable.companyId} = $1;`

    const res = await this.paramQuery(query, [id])
    return res !== null ? res : []
  }

  public async getCompanyRevenueUnits(userId: number): Promise<IRevenueUnit[]> {
    const { companyTable, userTable } = db

    const q = `SELECT ${companyTable.revenueUnits} FROM ${companyTable.tableName} WHERE 
    ${companyTable.id} IN (SELECT ${userTable.companyId} FROM ${userTable.tableName} WHERE 
    ${userTable.id} = $1 AND ${userTable.isDeleted} = false);`

    return this.paramQuery(q, [userId])
  }

  public async getCompanyFrequencyById(id: number): Promise<string> {
    const q = `SELECT ${db.companyTable.frequency} FROM ${db.companyTable.tableName} WHERE ${db.companyTable.id} = $1;`
    const res = await this.paramQuery(q, [id])
    return res[0] ? res[0][db.companyTable.frequency] : 'q'
  }

  public async getDataToCalculateImpactReport(
    companyId: number
  ): Promise<IRawDataForImpactReport> {
    const today = DateHelper.getYYYY_MM_DDString(
      DateHelper.removeTimestampFromDate(new Date())
    )
    const companySkills: ISkill[] = await this.getSkillsByCompanyID(companyId)
    const users: IUser[] = await this.getUsersByCompanyId(companyId)
    const roles: IRole[] = await this.getRolesByCompanyId(companyId)

    if (users !== null && companySkills != null) {
      const skillPerformances: ISkillPerformance[] = await this.getSkillPerformancesForUsers(
        users,
        today
      )
      if (
        companySkills.length > 0 &&
        users.length > 0 &&
        skillPerformances.length > 0
      ) {
        return {
          companyId,
          companySkills,
          users,
          skillPerformances,
          roles
        }
      }
    }
    return null
  }

  public async getOrgIdByUserId(userId: number): Promise<string> {
    const { companyTable, userTable } = db
    const q = `SELECT ${companyTable.crmId} FROM ${companyTable.tableName} WHERE
     ${companyTable.id} IN (SELECT ${userTable.companyId} FROM 
     ${userTable.tableName} WHERE ${userTable.id} = $1 AND ${userTable.isDeleted} = false);`

    const results = await this.paramQuery(q, [userId])
    return results[0][companyTable.crmId] !== undefined
      ? results[0][companyTable.crmId]
      : null
  }

  public async getDesiredBehaviorTargetNameIdByUserId(
    userId: number
  ): Promise<IDesiredBehavior[]> {
    const usersRole = await this.getUserRoleByUserId(userId)
    const usersCompanyId = await this.getCompanyIdFromUserId(userId)
    const {
      desiredBehaviorsTable: { id, name, roleId, companyId, tableName, target }
    } = db
    let query = `SELECT ${id}, ${name}, ${target} FROM ${tableName} WHERE ${companyId} = ${usersCompanyId} `
    query += `AND ${roleId} = ${usersRole};`
    return this.paramQuery(query, [])
  }

  public async getBehaviorPerformanceByDateRange(
    userId: number,
    desiredBehaviorId: number,
    startDate: string,
    endDate: string
  ): Promise<number> {
    const {
      performance,
      tableName,
      ownerId,
      date,
      behaviorId
    } = db.behaviorsTable
    const query = `SELECT SUM(${performance}) FROM ${tableName} WHERE ${ownerId} = $1 AND ${behaviorId} = $2 AND ${date} BETWEEN $3 AND $4;`
    const result = await this.paramQuery(query, [
      userId,
      desiredBehaviorId,
      startDate,
      endDate
    ])

    return result && result[0] && result[0].sum
      ? parseInt(result[0].sum, 10)
      : 0
  }

  public async getSkillsByDateRange(
    userId: number,
    startDate: string,
    endDate: string
  ): Promise<IScorecardSkillsDTO[]> {
    const { skillPerformanceTable, skillsTable } = db
    const { ownerId, performance, skillID } = skillPerformanceTable
    const { benchmark, id, stageIndex, unit, userFacingName } = skillsTable

    const query = `SELECT SUM(${skillPerformanceTable.tableName}.${performance}) AS Performance, ${skillsTable.tableName}.${benchmark},
      ${skillsTable.tableName}.${userFacingName}, ${skillsTable.tableName}.${unit}, ${skillsTable.tableName}.${stageIndex}
      FROM ${skillPerformanceTable.tableName} INNER JOIN ${skillsTable.tableName} ON ${skillPerformanceTable.tableName}.${skillID} = ${skillsTable.tableName}.${id}
      WHERE date between $2 and $3 AND ${skillPerformanceTable.tableName}.${ownerId} = $1
      GROUP BY ${skillsTable.tableName}.${userFacingName}, ${skillsTable.tableName}.${unit}, ${skillsTable.tableName}.${stageIndex}, ${skillsTable.tableName}.${benchmark};`

    return this.paramQuery(query, [userId, startDate, endDate])
  }

  public async getPersonQuadrantStats(
    userId: number,
    metricsFromMetricsApi: IMetric[],
    terms: ITerm[]
  ): Promise<APIQuadrantStats> {
    try {
      const coordinate: ICoordinate = await this.getMostRecentCoordinateForUser(
        userId
      )
      return this.translateCoordinateToAPIQuadrantStatsInterface(
        coordinate,
        metricsFromMetricsApi,
        terms
      )
    } catch (err) {
      return {
        xMetrics: [],
        yMetrics: []
      }
    }
  }

  public async getMostRecentCoordinateForUser(
    userId: number
  ): Promise<ICoordinate> {
    const { tableName, ownerId, lastComputedDate } = db.coordinatesTable
    const query = `SELECT * FROM ${tableName} WHERE ${ownerId} = $1 ORDER BY ${lastComputedDate} DESC LIMIT 1;`
    const result = await this.paramQuery(query, [userId])
    return result && result[0] ? result[0] : null
  }

  public translateCoordinateToAPIQuadrantStatsInterface(
    coordinate: ICoordinate,
    metricsFromMetricsApi: IMetric[],
    terms: ITerm[]
  ): APIQuadrantStats {
    const coordinateData = coordinate.coordinate_calc_data
    const keys = Object.keys(coordinateData)
    const xMetrics: APIXmetrics[] = []
    const yMetrics: APIYmetrics[] = []

    keys.forEach(key => {
      const metric = coordinateData[key]
      const metricId = parseInt(key, 10)
      const metricWithTermId = metricsFromMetricsApi.find(
        m => m.id === metricId
      )
      const term = terms.find(term => term.id === metricWithTermId.termId)

      if (metric.axis === 'x') {
        xMetrics.push({
          displayName: metric.name,
          goal: metric.target,
          isCurrentStatus: term ? term.isCurrentStatus : false,
          max: metric.max_credit,
          numberTargetPeriods: metric.num_target_periods,
          performance: metric.performance,
          quarterToDateTarget: metric.target,
          rollingWorkdays: metric.rolling_workdays,
          unit: metric.unit === ' ' ? '' : metric.unit,
          weight: metric.weight
        })
      } else {
        if (metric.performances) {
          metric.performances.forEach(p => {
            yMetrics.push({
              displayName: metric.name,
              endDate: p.endDate,
              goal: p.target,
              isCurrentStatus: term ? term.isCurrentStatus : false,
              numberTargetPeriods: metric.num_target_periods,
              performance: p.performance,
              quarterToDateTarget: p.nonPacedTarget || p.target,
              rollingWorkdays: metric.rolling_workdays,
              startDate: p.startDate,
              unit: metric.unit === ' ' ? '' : metric.unit,
              weight: metric.weight
            })
          })
        }
      }
    })
    return {
      xMetrics,
      yMetrics
    }
  }

  public async getUserRoleByUserId(userId: number): Promise<number> {
    const { userTable } = db
    const q = `SELECT ${userTable.roleId} FROM ${userTable.tableName} WHERE 
    ${userTable.id} = $1 AND ${userTable.isDeleted} = false;`

    const roleObject: object[] = await this.paramQuery(q, [userId])

    return roleObject[0] ? roleObject[0][db.userTable.roleId] : null
  }

  private async fetchCoordinatesByDate(
    date: Date,
    companyId: number
  ): Promise<ICoordDateNameId[]> {
    const daysBackArr = [
      0,
      -DateHelper.daysInWeek,
      -DateHelper.daysInWeek * 2,
      -DateHelper.daysInWeek * 3,
      -DateHelper.daysInWeek * 4
    ]
    const dates = daysBackArr.map(daysBack =>
      DateHelper.getYYYY_MM_DDString(
        DateHelper.getNewDateByAddingDays(date, daysBack)
      )
    )

    const { coordinatesTable, userTable } = db
    const q = `SELECT c.${coordinatesTable.ownerId},
    c.${coordinatesTable.coordinates}, c.${coordinatesTable.lastComputedDate},
    u.${userTable.name}, u.${userTable.manager}, u.${userTable.role}
    FROM ${coordinatesTable.tableName} c LEFT JOIN ${userTable.tableName} u
    ON u.${userTable.id} = c.${coordinatesTable.ownerId}
    WHERE c.${coordinatesTable.companyId} = $1 AND
    (c.${coordinatesTable.lastComputedDate} = $2 OR
    c.${coordinatesTable.lastComputedDate} = $3 OR
    c.${coordinatesTable.lastComputedDate} = $4 OR
    c.${coordinatesTable.lastComputedDate} = $5 OR
    c.${coordinatesTable.lastComputedDate} = $6);`

    return this.paramQuery(q, [companyId, ...dates])
  }

  private missingCoordinatesForDate(
    date: string,
    coordinates: ICoordDateNameId[]
  ): boolean {
    return (
      coordinates.filter(
        c =>
          date ===
          DateHelper.getYYYY_MM_DDString(new Date(c.last_computed_date))
      ).length === 0
    )
  }

  private async getMostRecentCoordinates(
    companyId: number
  ): Promise<ICoordDateNameId[]> {
    const today = new Date()
    let coordinates = await this.fetchCoordinatesByDate(today, companyId)
    if (
      this.missingCoordinatesForDate(
        DateHelper.getYYYY_MM_DDString(today),
        coordinates
      )
    ) {
      for (let i = 0; i < 10; i++) {
        const dateInQuestion: Date = DateHelper.getNewDateByAddingDays(
          today,
          -i
        )
        /* eslint-disable no-await-in-loop */
        coordinates = await this.fetchCoordinatesByDate(
          dateInQuestion,
          companyId
        )
        if (
          !this.missingCoordinatesForDate(
            DateHelper.getYYYY_MM_DDString(dateInQuestion),
            coordinates
          )
        ) {
          break
        }
      }
    }
    return coordinates
  }

  public async getQuadrantData(companyId: number): Promise<APIQuadrantData[]> {
    const coordinates: ICoordDateNameId[] = await this.getMostRecentCoordinates(
      companyId
    )
    const ownerIdToQuadrantData: Map<number, APIQuadrantData> = new Map()
    coordinates.forEach(coord => {
      if (!ownerIdToQuadrantData.has(coord.owner_id)) {
        const temp = <APIQuadrantData>{}
        temp.managerId = coord.manager
        temp.name = coord.full_name
        temp.personId = coord.owner_id
        temp.points = [
          {
            date: coord.last_computed_date,
            x: coord.coordinates.x,
            y: coord.coordinates.y
          }
        ]
        temp.role = coord.role
        ownerIdToQuadrantData.set(coord.owner_id, temp)
      } else {
        const current = ownerIdToQuadrantData.get(coord.owner_id)
        current.points.push({
          date: coord.last_computed_date,
          x: coord.coordinates.x,
          y: coord.coordinates.y
        })
      }
    })

    const ownerIds = [...ownerIdToQuadrantData.keys()]
    return ownerIds.map(id => ownerIdToQuadrantData.get(id))
  }

  public async getManagersByUserId(userId: number): Promise<object[]> {
    const { managersTable, userTable } = db
    const q = `SELECT ${managersTable.managerId} FROM 
    ${managersTable.tableName} WHERE ${managersTable.companyId} 
    (SELECT ${userTable.companyId} FROM ${userTable.tableName} WHERE
     ${userTable.id} = $1 AND ${userTable.isDeleted} = false);`

    return this.paramQuery(q, [userId])
  }

  public async getTeams(companyId: number): Promise<APITeam[]> {
    const { userTable, imagesTable } = db

    const q = `SELECT ${userTable.tableName}.${userTable.name}, ${userTable.tableName}.${userTable.id}, 
    ${userTable.tableName}.${userTable.manager}, ${userTable.tableName}.${userTable.role}, 
    ${imagesTable.tableName}.${imagesTable.name}, ${imagesTable.ext}, ${userTable.roleId} FROM ${userTable.tableName} 
    LEFT JOIN ${imagesTable.tableName} ON ${userTable.tableName}.${userTable.imageId} = ${imagesTable.tableName}.${imagesTable.id} 
    WHERE ${userTable.companyId} = ${companyId} AND ${userTable.isDeleted} = false;`

    return this.formTeams(await this.query(q))
  }

  public async getTeamImpactReportByManagerId(userId: number): Promise<any> {
    return this.findUsersWithImpactReport([userId])
  }

  private async findUsersWithImpactReport(userIds: number[]): Promise<any> {
    if (!userIds.length) {
      return []
    }

    const { impactReportTable, userTable } = db
    const q = `SELECT * FROM ${impactReportTable.tableName} WHERE ${
      impactReportTable.ownerId
    }
    IN (SELECT ${userTable.id} FROM ${userTable.tableName} WHERE ${
      userTable.manager
    } IN 
    ${this.parameterizeIdsForQuery(userIds)} AND ${
      userTable.isDeleted
    } = false);`

    const impactResults: ImpactReportDTO[] = await this.paramQuery(q, userIds)
    return impactResults.length < 1
      ? this.recurseTreeForImpactReports(userIds)
      : impactResults
  }

  private async recurseTreeForImpactReports(userIds: number[]): Promise<any> {
    const { userTable } = db
    const q2 = `SELECT ${userTable.id} FROM ${userTable.tableName}
      WHERE ${userTable.manager} IN ${this.parameterizeIdsForQuery(userIds)};`
    const newIds: number[] = await this.paramQuery(q2, userIds)
    return newIds !== null
      ? this.findUsersWithImpactReport(newIds.map(id => id[userTable.id]))
      : []
  }

  private parameterizeIdsForQuery(userIds: number[], offset = 0): string {
    return `(${userIds.reduce((previousValue: string, value: number, i) => {
      return (
        previousValue +
        `$${i + offset + 1}` +
        (i === userIds.length - 1 ? '' : ',')
      )
    }, '')})`
  }

  private formTeams(users: any[]): APITeam[] {
    const managers: number[] = []

    users.forEach(user => {
      if (user.manager && !(managers.indexOf(user.manager) > -1)) {
        managers.push(user.manager)
      }
    })

    const teams: APITeam[] = []
    const { id, name, roleId, manager } = db.userTable
    users.forEach(user => {
      if (managers.indexOf(user[id]) > -1) {
        const managerId: number = user.manager ? user.manager : -1
        teams.push({
          manager: {
            id: user[id],
            name: user[name],
            managerId,
            role: user.role,
            roleId: user[roleId] || -1,
            profilePicture:
              user.name && user.ext ? `${user.name}.${user.ext}` : ''
          },
          members: []
        })
      }
    })

    for (let i = 0; i < users.length; i++) {
      for (let j = 0; j < teams.length; j++) {
        if (users[i][manager] === teams[j].manager.id) {
          const managerId: number = users[i].manager ? users[i].manager : -1
          teams[j].members.push({
            id: users[i][id],
            managerId,
            name: users[i][name],
            role: users[i].role,
            roleId: users[i][roleId] || -1,
            profilePicture:
              users[i].name && users[i].ext
                ? `${users[i].name}.${users[i].ext}`
                : ''
          })
          break
        }
      }
    }
    return teams
  }

  public async onboardCompany(
    company: APIOnboardCompany,
    connection: pg
  ): Promise<ICompanyId[]> {
    let q = `INSERT INTO ${db.companyTable.tableName} (${db.companyTable.companyName}, ${db.companyTable.crmId}, ${db.companyTable.frequency}, `
    q += `${db.companyTable.percentOutboundLeads}, ${db.companyTable.revenueUnits}, ${db.companyTable.token}) VALUES `
    q += `($1, $2, $3, $4, $5, $6) RETURNING ${db.companyTable.id}`
    const values = [
      company.company_name,
      company.crm_id,
      company.frequency,
      company.percent_outbound_leads,
      company.revenue_units,
      company.token
    ]
    return this.paramQueryWithCustomConnection(q, values, connection)
  }

  public async onboardGoals(
    goals: IRevenueGoalInsert[],
    connection: pg
  ): Promise<object> {
    let q = `INSERT INTO ${db.revenueGoalTable.tableName} (${db.revenueGoalTable.ownerId}, ${db.revenueGoalTable.goal}, `
    q += `${db.revenueGoalTable.startDate}, ${db.revenueGoalTable.endDate}) VALUES `
    let paramIter = 1
    const values = []
    goals.forEach((g: IRevenueGoalInsert, idx) => {
      q += `($${paramIter++}, $${paramIter++})`
      q += idx < goals.length - 1 ? ', ' : ' '
      values.push(g.owner_id, g.goal, g.start_date, g.end_date)
    })
    return this.paramQueryWithCustomConnection(q, values, connection)
  }

  public async onboardRoles(
    companyId: number,
    roles: string[],
    connection: pg
  ): Promise<IRoleIdName[]> {
    let q = `INSERT INTO ${db.rolesTable.tableName} (${db.rolesTable.companyId}, ${db.rolesTable.name}) VALUES `
    let paramIter = 1
    const values = []
    roles.forEach((r, idx) => {
      q += `($${paramIter++}, $${paramIter++})`
      q += idx < roles.length - 1 ? ', ' : ' '
      values.push(companyId, r)
    })
    q += `RETURNING ${db.rolesTable.id}, ${db.rolesTable.name};`
    return this.paramQueryWithCustomConnection(q, values, connection)
  }

  public async onboardSkills(
    skills: ISkill[],
    companyId: number,
    connection: pg
  ): Promise<object> {
    let q = `INSERT INTO ${db.skillsTable.tableName} (${db.skillsTable.name}, ${db.skillsTable.type}, ${db.skillsTable.companyId}, `
    q += `${db.skillsTable.benchmark}, ${db.skillsTable.stageIndex}, ${db.skillsTable.precedence}, ${db.skillsTable.userFacingName}, `
    q += `${db.skillsTable.unit}, ${db.skillsTable.query}) VALUES `
    const values = []
    let i = 1
    skills.forEach((skill, idx) => {
      q += `($${i++}, $${i++}, $${i++}, $${i++}, $${i++}, $${i++}, $${i++}, $${i++}, $${i++})`
      q += idx < skills.length - 1 ? ', ' : ';'
      values.push(
        skill.name,
        skill.type,
        companyId,
        skill.benchmark,
        skill.stage_index,
        skill.precedence,
        skill.user_facing_name,
        skill.unit,
        skill.query
      )
    })
    return this.paramQueryWithCustomConnection(q, values, connection)
  }

  public async onboardUsers(
    users: APIOnboardUser[],
    roles: IRoleIdName[],
    companyId: number,
    connection: pg
  ): Promise<INameWithId[]> {
    let q = `INSERT INTO ${db.userTable.tableName} (${db.userTable.name}, ${db.userTable.role}, `
    q += `${db.userTable.companyId}, ${db.userTable.crmID}, ${db.userTable.email}, ${db.userTable.roleId}) VALUES `
    const values = []
    let i = 1
    users.forEach((user, idx) => {
      q += `($${i++}, $${i++}, $${i++}, $${i++}, $${i++}, $${i++})`
      q += idx === users.length - 1 ? ' ' : ', '
      values.push(
        user.full_name,
        user.role,
        companyId,
        user.crm_id,
        user.email,
        this.getRoleForOnboardingUser(user.role, roles)
      )
    })
    q += ` RETURNING ${db.userTable.id}, ${db.userTable.name};`
    return this.paramQueryWithCustomConnection(q, values, connection)
  }

  public async onboardBehaviors(
    behaviors: IOnboardBehavior[],
    connection: pg,
    companyId: number
  ): Promise<object> {
    let q = `INSERT INTO ${db.desiredBehaviorsTable.tableName} (${db.desiredBehaviorsTable.name}, ${db.desiredBehaviorsTable.companyId}, `
    q += `${db.desiredBehaviorsTable.target}, ${db.desiredBehaviorsTable.roleId}, ${db.desiredBehaviorsTable.query}) VALUES `
    let i = 1
    const values = []
    behaviors.forEach((b: IOnboardBehavior, idx) => {
      q += `($${i++}, $${i++}, $${i++}, $${i++}, $${i++})`
      q += idx === behaviors.length - 1 ? ';' : ', '
      values.push(b.name, companyId, b.target, b.roleId, b.query)
    })
    return this.paramQueryWithCustomConnection(q, values, connection)
  }

  public async getSFOAuthForCompany(companyId: number): Promise<ISFOAuthInfo> {
    const q = `SELECT ${db.companyTable.token}, ${db.companyTable.clientSecret}, ${db.companyTable.clientId}, ${db.companyTable.companyName}, ${db.companyTable.crmId} FROM ${db.companyTable.tableName} WHERE ${db.companyTable.id} = $1 LIMIT 1;`
    const res = await this.paramQuery(q, [companyId])
    const sfSecret = process.env.SF_SECRET
    const companyName = res[0][db.companyTable.companyName]
    const crmId = res[0][db.companyTable.crmId]
    const encryptedSecret = res[0][db.companyTable.clientSecret]
    const encryptedToken = res[0][db.companyTable.token]
    const clientId = res[0][db.companyTable.clientId]

    if (res[0]) {
      const key = `${sfSecret}${crmId}${companyName}`
      const clientSecret = CryptoFunctions.decrypt(encryptedSecret, key)
      const token = CryptoFunctions.decrypt(encryptedToken, key)
      return {
        client_secret: clientSecret,
        client_id: clientId,
        token
      }
    }
    return null
  }

  public async updateUsersManager(
    users: IUserAndManager[],
    connection: pg
  ): Promise<object> {
    let q = `UPDATE ${db.userTable.tableName} set ${db.userTable.manager} = new_managers FROM (VALUES `
    users.forEach((u, idx) => {
      q += `(${u.userId}, ${u.managerId})`
      q += idx !== users.length - 1 ? ', ' : ''
    })
    q += `) as tmp(id, new_managers) WHERE tmp.id = ${db.userTable.tableName}.${db.userTable.id};`
    return this.paramQueryWithCustomConnection(q, [], connection)
  }

  private getRoleForOnboardingUser(
    roleName: string,
    roles: IRoleIdName[]
  ): number {
    const role = roles.filter((r: IRoleIdName) => r.name === roleName)
    return role.length ? role[0].id : null
  }

  public async getUserIdsAndCRMIDsByCRMID(
    crmIds: string[]
  ): Promise<IUserIdCrmId[]> {
    Logger.entering('PersistenceManager', 'getUserIdsAndCRMIDsByCRMID', {
      crmIds
    })
    if (!crmIds.length) {
      Logger.exiting('PersistenceManager', 'getUserIdsAndCRMIDsByCRMID', [])
      return []
    }
    let idx: number = 1
    const query = `SELECT ${db.userTable.id}, ${db.userTable.crmID} 
       FROM ${db.userTable.tableName} 
       WHERE ${db.userTable.crmID} IN (${crmIds.map(() => {
      return `$${idx++}`
    })});`

    return this.paramQuery(query, crmIds)
  }

  public async getUserImpactReportByOwnerId(
    ownerId: number
  ): Promise<ImpactReportDTO> {
    const impactReport = await this.paramQuery(
      `SELECT * FROM ${db.impactReportTable.tableName} WHERE ${db.impactReportTable.ownerId} = $1;`,
      [ownerId]
    )
    if (impactReport !== null && impactReport.length > 0) {
      impactReport[0][db.impactReportTable.winSkills] = JSON.stringify(
        JSON.parse(impactReport[0][db.impactReportTable.winSkills])
      )
      return impactReport[0]
    }
    return null
  }

  public openConnection(): any {
    const connection = new pg.Client(this.databaseURI)
    connection.connect()
    return connection
  }

  public async persistImpactReport(
    impactReport: IFormattedImpactReportData,
    companyId: number
  ): Promise<void> {
    const today = DateHelper.getYYYY_MM_DDString(
      DateHelper.removeTimestampFromDate(new Date())
    )
    const query = await PersistImpactReportHelper.getImpactReportInsertStatement(
      impactReport,
      companyId,
      today
    )
    await this.query(query)
  }

  public async persistSkillPerformances(
    skills: ISkillPerformance[],
    connection: pg.Client
  ): Promise<boolean> {
    return this.executeCommit(
      true,
      PersistenceManager.prepareSkillPerformanceInsert(skills),
      connection
    )
  }

  public persistXMetrics(
    xDTOS: IBehavior[],
    connection: pg.Client
  ): Promise<boolean> {
    return this.executeCommit(
      true,
      PersistenceManager.prepareXDTOsInsert(xDTOS),
      connection
    )
  }

  public persistYMetrics(
    yDTOS: IResult[],
    connection: pg.Client
  ): Promise<boolean> {
    return this.executeCommit(
      true,
      PersistenceManager.prepareYDTOsInsert(yDTOS),
      connection
    )
  }

  private static prepareXDTOsInsert(xDTOs: IBehavior[]): string {
    if (!xDTOs || xDTOs.length === 0) {
      return ''
    }
    let q = `INSERT INTO ${db.behaviorsTable.tableName} `
    q += `(${db.behaviorsTable.ownerId}, `
    q += `${db.behaviorsTable.performance}, `
    q += `${db.behaviorsTable.date}, `
    q += `${db.behaviorsTable.behaviorId}) VALUES `

    for (let i: number = 0; i < xDTOs.length; i++) {
      q += `(${xDTOs[i].owner_id}, ${xDTOs[i].performance}, '${xDTOs[i].date}', ${xDTOs[i].behavior_id})`
      if (i < xDTOs.length - 1) {
        q += ', '
      }
    }
    q += `ON CONFLICT ON CONSTRAINT ${db.behaviorsTable.upsertConstraint}\n`
    q += `DO UPDATE SET ${db.behaviorsTable.performance} = EXCLUDED.${db.behaviorsTable.performance};`
    return q
  }

  private static prepareYDTOsInsert(yDTOs: IResult[]): string {
    if (!yDTOs || yDTOs.length === 0) {
      return ''
    }
    let q = `INSERT INTO ${db.resultsTable.tableName}`
    q += `(${db.resultsTable.ownerId}, `
    q += `${db.resultsTable.performance}, `
    q += `${db.resultsTable.date}, `
    q += `${db.resultsTable.resultId}) VALUES `

    for (let i: number = 0; i < yDTOs.length; i++) {
      q += `(${yDTOs[i].owner_id}, ${yDTOs[i].performance}, '${yDTOs[i].date}', ${yDTOs[i].result_id})`
      if (i < yDTOs.length - 1) {
        q += ', '
      }
    }
    q += `ON CONFLICT ON CONSTRAINT ${db.resultsTable.upsertConstraint}\n`
    q += `DO UPDATE SET ${db.resultsTable.performance} = EXCLUDED.${db.resultsTable.performance};`
    return q
  }

  private static prepareSkillPerformanceInsert(
    skillDTOs: ISkillPerformance[]
  ): string {
    if (!skillDTOs || skillDTOs.length === 0) {
      return ''
    }
    let stmt = ''
    stmt += `INSERT INTO ${db.skillPerformanceTable.tableName}`
    stmt += `(${db.skillPerformanceTable.ownerId}, `
    stmt += `${db.skillPerformanceTable.performance}, `
    stmt += `${db.skillPerformanceTable.date}, `
    stmt += `${db.skillPerformanceTable.skillID}) VALUES `
    for (let i: number = 0; i < skillDTOs.length; i++) {
      stmt += `(${skillDTOs[i].owner_id}, ${skillDTOs[i].performance}, '${skillDTOs[i].date}', ${skillDTOs[i].skill_id})`
      if (i < skillDTOs.length - 1) {
        stmt += ', '
      }
    }
    stmt += `ON CONFLICT ON CONSTRAINT ${db.skillPerformanceTable.upsertConstraint}\n`
    stmt += `DO UPDATE SET ${db.skillPerformanceTable.performance} = EXCLUDED.${db.skillPerformanceTable.performance};`
    return stmt
  }

  private query(query: string): Promise<any> {
    const connection = this.openConnection()
    return new Promise(resolve => {
      connection.query(query, (err, res) => {
        if (err) {
          const msg = `ERROR: PersistenceManager.ts -> query(). Failed query: ${query}. err: ${err.message}\n`
          Logger.info(msg, 'err')
          resolve(null)
          connection.end()
        } else {
          connection.end()
          resolve(res.rows)
        }
      })
    })
  }

  public async getUserNameById(userId: number): Promise<string> {
    const results = await this.query(
      `SELECT ${db.userTable.name} FROM ${db.userTable.tableName} WHERE ${db.userTable.id} = ${userId};`
    )
    if (results !== null) {
      return results[0][db.userTable.name]
        ? results[0][db.userTable.name]
        : null
    }
    return results
  }

  private queryWithConnection(query: string, connection: pg): Promise<any> {
    return new Promise((resolve, reject) => {
      connection.query(query, err => {
        if (err) {
          const msg = `ERROR: PersistenceManager.ts -> queryWithConnection(). Failed query: ${query}. err: ${err.message}\n`
          Logger.info(msg, 'err')
          reject(err)
        } else {
          resolve(true)
        }
      })
    })
  }

  public async setUserGoal(
    decodedAuthToken: IDecodedAuthToken,
    goal: number,
    startDate: string,
    endDate: string
  ): Promise<object> {
    if (
      PersistenceManager.isValidDateString(startDate) &&
      PersistenceManager.isValidDateString(endDate)
    ) {
      let code = 200
      let q = `INSERT INTO ${db.revenueGoalTable.tableName} (${db.revenueGoalTable.ownerId}, `
      q += `${db.revenueGoalTable.goal}, ${db.revenueGoalTable.startDate}, ${db.revenueGoalTable.endDate})`
      q += ' VALUES ($1, $2, $3, $4);'
      if (
        (await this.paramQuery(q, [
          decodedAuthToken.userId,
          goal,
          startDate,
          endDate
        ])) === null
      ) {
        code = 1005
        return { error: errorCodes[code], code }
      }
      return { code, error: errorCodes[code] }
    }
    const msg = `PersistanceManager.ts -> setUserGoal() invalid date(s) for user goal: Start Date: ${startDate} End Date: ${endDate}`
    Logger.info(msg, 'err')
    const code = 5001
    return { error: errorCodes[code], code }
  }

  private static isValidDateString(date: string): boolean {
    return new Date(date).toString() !== 'Invalid Date'
  }

  public async getPreviousPasswords(userId: number): Promise<string[]> {
    let q = `SELECT ${db.passwordHistoriesTable.passwords} FROM ${db.passwordHistoriesTable.tableName}`
    q += ` WHERE ${db.passwordHistoriesTable.userId} = $1;`
    const passwords = await this.paramQuery(q, [userId])
    if (passwords && passwords.length > 0) {
      return passwords[0][db.passwordHistoriesTable.passwords]
    }
    return []
  }

  public async updatePassword(
    email: string,
    passwordHash: string,
    previousHashes: string[],
    userId: number
  ): Promise<number> {
    const { userTable, passwordHistoriesTable } = db
    previousHashes.unshift(passwordHash)
    while (previousHashes.length > 5) {
      previousHashes.pop()
    }
    const q = `UPDATE ${userTable.tableName} SET ${userTable.passwordHash} = 
    $1 WHERE ${userTable.email} = $2;`

    const insert = `INSERT INTO ${passwordHistoriesTable.tableName} (${
      passwordHistoriesTable.userId
    },
      ${passwordHistoriesTable.passwords}) SELECT ${userId}, '${JSON.stringify(
      previousHashes
    )}'`
    const upsert = `UPDATE ${passwordHistoriesTable.tableName} SET ${
      passwordHistoriesTable.passwords
    } = 
      '${JSON.stringify(previousHashes)}' WHERE ${
      passwordHistoriesTable.userId
    } = ${userId}`
    const q1 = `WITH UPSERT AS (${upsert} RETURNING *) ${insert} WHERE NOT EXISTS (SELECT * FROM upsert);`
    if ((await this.paramQuery(q, [passwordHash, email])) === null) {
      return 404
    }
    const secondRes = await this.query(q1)
    if (secondRes === null) {
      return 404
    }
    return 200
  }

  // Database operations
  public async getCompanyIdFromUserId(userId: number): Promise<number> {
    const companyId: number = await this.query(
      `SELECT ${db.userTable.companyId} FROM ${db.userTable.tableName} WHERE ${db.userTable.id} = ${userId};`
    )
    return companyId ? companyId[0][db.userTable.companyId] : null
  }

  public async getCompanyNameFromCompanyId(
    companyId: number
  ): Promise<object[]> {
    const { companyName, id, tableName } = db.companyTable
    const q = `SELECT ${companyName} FROM ${tableName} WHERE ${id}=$1;`
    return this.paramQuery(q, [companyId])
  }

  private async getRevenueGoalsByOwnerIds(
    userIds: number[],
    daysPast: number,
    dateOfCalculation: string
  ): Promise<IRevenueGoal[]> {
    const { tableName, startDate, ownerId } = db.revenueGoalTable
    const startOfDateRange = DateHelper.getYYYY_MM_DDString(
      DateHelper.getNewDateByAddingDays(new Date(dateOfCalculation), -daysPast)
    )
    const q = `SELECT * FROM ${tableName} WHERE ${ownerId} IN 
    ${this.parameterizeIdsForQuery(userIds)}
     AND ${startDate} <= '${dateOfCalculation}' AND ${startDate} >= '${startOfDateRange}';`
    return this.paramQuery(q, userIds)
  }

  private async getDesiredBehaviorsByCompanyId(
    companyId: number,
    roleId?: number
  ): Promise<IDesiredBehavior[]> {
    let query: string = `SELECT * FROM ${db.desiredBehaviorsTable.tableName} WHERE `
    query += `${db.desiredBehaviorsTable.companyId} = $1`
    return roleId
      ? this.paramQuery(
          `${query}AND ${db.desiredBehaviorsTable.roleId} = $2;`,
          [companyId, roleId]
        )
      : this.paramQuery(`${query};`, [companyId])
  }

  private async getBehaviorRules(
    behaviors: IDesiredBehavior[]
  ): Promise<IBehaviorRule[]> {
    let query = `SELECT * FROM ${db.behaviorRuleTable.tableName} WHERE ${db.behaviorRuleTable.behaviorId} IN (`
    const ids: number[] = []
    for (let i: number = 0; i < behaviors.length; i++) {
      ids.push(behaviors[i].id)
      query += `$${i + 1}`
      if (i !== behaviors.length - 1) {
        query += ', '
      }
    }
    query += ');'
    return this.paramQuery(query, ids)
  }

  public async getUsersManagedByUserId(userId: number): Promise<number[]> {
    const { userTable } = db
    const q = `SELECT ${userTable.id} FROM ${userTable.tableName} WHERE
      ${userTable.manager} = $1 AND ${userTable.isDeleted} = false;
      `
    const result: number[] = await this.paramQuery(q, [userId])

    if (
      result &&
      result.length &&
      Object.prototype.hasOwnProperty.call(result[0], 'id')
    ) {
      return result.map((idObject: any) => idObject.id)
    }

    return result
  }

  public async getAllUsersManagedByUserId(userId: number): Promise<number[]> {
    return await this.getUsersManagedByUserIds([userId])
  }

  public async getUsersManagedByUserIds(userIds: number[]): Promise<number[]> {
    if (!userIds.length) {
      return userIds
    }

    const { userTable } = db
    const q = `SELECT ${userTable.id} FROM ${userTable.tableName} WHERE
    ${userTable.isDeleted} = false AND 
    ${userTable.manager} IN ${this.parameterizeIdsForQuery(userIds)};`

    const result: { id: number }[] = await this.paramQuery(q, userIds)
    if (!result) {
      return []
    }

    const users = result.map(user => user.id)
    return [...users, ...(await this.getUsersManagedByUserIds(users))]
  }

  public async getManagerOfUser(userId: number): Promise<number> {
    const { userTable } = db
    const q = `SELECT ${userTable.manager} FROM ${userTable.tableName} WHERE 
    ${userTable.id} = $1 AND ${userTable.isDeleted} = false;`

    const res = await this.paramQuery(q, [userId])
    if (res[0]) {
      return res[0].manager
    }
    return null
  }

  public async getInteractionsForUser(
    ownerId: number
  ): Promise<APIInteraction[]> {
    const { interactions, userTable } = db
    const q = `SELECT ${userTable.name}, ${interactions.dateTime}, ${interactions.message}
    FROM ${interactions.tableName}
    LEFT JOIN ${userTable.tableName} u ON u.${userTable.id} = ${interactions.createdById}
    WHERE ${interactions.ownerId} = $1;`

    const res = await this.paramQuery(q, [ownerId])

    return res.map(interaction => {
      return {
        message: interaction[interactions.message],
        createdBy: interaction[userTable.name],
        enteredDateTime: parseInt(interaction[interactions.dateTime], 10)
      }
    })
  }

  public async getPreviousInteractions(
    managerId: number,
    year: number,
    month: number,
    date: number
  ): Promise<IPreviousManagerInteractions> {
    const interactionMonth = DateHelper.getMillisecondsInMonth(
      year,
      month,
      date
    )
    const { interactions } = db
    const q = `SELECT COUNT(${interactions.message}) AS interactions
    FROM ${interactions.tableName}   
    WHERE ${interactions.createdById} = $1
    AND ${interactions.dateTime} BETWEEN ${interactionMonth[0]} AND ${interactionMonth[1]}`

    const result = await this.paramQuery(q, [managerId])
    if (result && result[0]) {
      return result[0]
    }
    return { interactions: '0' }
  }

  public async isUserManagerOfManagers(userId: number): Promise<boolean> {
    const { userTable } = db
    const q = `SELECT COUNT(*) FROM ${userTable.tableName} WHERE ${userTable.manager} = $1 
    AND ${userTable.id} IN (SELECT ${userTable.manager} FROM ${userTable.tableName})`
    const response = await this.paramQuery(q, [userId])
    return response.length > 0
  }

  public async getManagerListUnderUser(
    userId: number
  ): Promise<IManagerList[]> {
    const { userTable } = db
    const q = `SELECT ${userTable.name} as name, ${userTable.id} FROM ${userTable.tableName}  
    WHERE ${userTable.id} = $1 OR (${userTable.manager} = $1 AND ${userTable.id} IN 
    (SELECT ${userTable.manager} FROM ${userTable.tableName}))`

    return this.paramQuery(q, [userId])
  }

  public async getManagerNameById(managerId: number): Promise<string> {
    const { id, name, tableName } = db.userTable
    const q = `SELECT ${name} FROM ${tableName} WHERE ${id} = $1`

    return this.paramQuery(q, [managerId])
  }

  public async getTotalInteractionsByMonth(
    userId: number,
    year: number,
    month: number,
    date: number
  ): Promise<ICurrentManagerInteractions[]> {
    const interactionMonth = DateHelper.getMillisecondsInMonth(
      year,
      month,
      date
    )
    const { interactions } = db
    const q = `SELECT ${interactions.createdById} AS id, 
    COUNT(${interactions.message}) AS interactions 
    FROM ${interactions.tableName} WHERE ${interactions.createdById} = $1  
    AND ${interactions.tableName}.${interactions.dateTime} BETWEEN ${interactionMonth[0]} AND ${interactionMonth[1]}
    GROUP BY ${interactions.createdById}`

    return this.paramQuery(q, [userId])
  }

  private async getSkillsByCompanyID(companyId: number): Promise<ISkill[]> {
    const query = `SELECT * FROM ${db.skillsTable.tableName} WHERE
      ${db.skillsTable.companyId} = $1;`
    return this.paramQuery(query, [companyId])
  }

  public async getUsersByCompanyId(companyId: number): Promise<IUser[]> {
    const {
      accountType,
      crmID,
      email,
      id,
      isDeleted,
      manager,
      metricProfileId,
      name,
      role,
      roleId,
      startDate,
      tableName
    } = db.userTable
    const query = `SELECT ${id}, ${crmID}, ${email}, ${manager}, ${metricProfileId}, ${name}, ${role},
     ${db.userTable.companyId}, ${roleId}, ${startDate}, ${accountType}
      FROM ${tableName} WHERE
      ${db.userTable.companyId} = $1 AND ${isDeleted} = false;`

    return this.paramQuery(query, [companyId])
  }

  public async getUserStartDate(userId: number): Promise<Date> {
    const { userTable } = db
    const q = `SELECT ${userTable.startDate} FROM ${userTable.tableName} 
    WHERE ${userTable.id} = $1;`

    const res = await this.paramQuery(q, [userId])

    if (res && res[0] && res[0][userTable.startDate]) {
      return new Date(res[0][userTable.startDate])
    }
    return null
  }

  public async getUsersStartDateByCompanyId(
    companyId: number
  ): Promise<{ id: number; start_date: string }[]> {
    const { userTable } = db
    const q = `SELECT ${userTable.id}, ${userTable.startDate} FROM ${userTable.tableName} 
    WHERE ${userTable.companyId} = $1 AND ${userTable.isDeleted} = false;`

    return this.paramQuery(q, [companyId])
  }

  private async getSkillPerformancesForUsers(
    users: IUser[],
    today: string
  ): Promise<ISkillPerformance[]> {
    let query = `SELECT * FROM ${db.skillPerformanceTable.tableName} WHERE ${db.skillPerformanceTable.ownerId} IN ( `
    const ids: number[] = []
    for (let i = 0; i < users.length; i++) {
      ids.push(users[i][db.userTable.id])
      query += `$${i + 1}`
      if (i !== users.length - 1) {
        query += ', '
      }
    }
    const now = DateHelper.getTimeStampWithoutTimeZone(today)
    query += `) AND ${db.skillPerformanceTable.date} > ${now} - interval '90 days'
      ORDER BY ${db.skillPerformanceTable.ownerId}, ${db.skillPerformanceTable.skillID} ;`
    return this.paramQuery(query, ids)
  }

  public async updateLastSyncedDate(
    lastSyncedDate: string,
    orgId: string
  ): Promise<void> {
    const newDate = new Date(lastSyncedDate)
    if (!(newDate instanceof Date)) {
      const msg = `PersistenceManager.ts -> updateLastSyncedDate() Failed to parse valid date from Date String while updating the date string: ${lastSyncedDate}`
      Logger.info(msg, 'info')
    }
    const dateString = `(to_timestamp('${lastSyncedDate}', 'mm/dd/yyyy hh12:mi am'))`
    const query = `UPDATE ${db.companyTable.tableName} SET ${db.companyTable.lastSyncDateTime}=${dateString} WHERE ${db.companyTable.crmId}= $1;`

    await this.paramQuery(query, [orgId])
  }

  public async getUserEmailById(id: number): Promise<string> {
    const results = await this.query(
      `SELECT ${db.userTable.email} FROM ${db.userTable.tableName} WHERE ${db.userTable.id} = ${id};`
    )
    if (results !== null) {
      return results[0][db.userTable.email]
        ? results[0][db.userTable.email]
        : null
    }
    return results
  }

  public async getUserEmailAndNameById(
    id: number
  ): Promise<{ full_name: string; email: string }> {
    const { userTable } = db
    const q = `SELECT ${userTable.email}, ${userTable.name} FROM
    ${userTable.tableName} WHERE ${userTable.id} = $1;`

    const res = await this.paramQuery(q, [id])
    return res[0] || null
  }

  public async updateConfiguration(
    configuration: string,
    companyId: number
  ): Promise<object[]> {
    const { companyTable } = db
    const q = `UPDATE ${companyTable.tableName} SET ${companyTable.configuration}
    = $1 WHERE ${companyTable.id} = $2`
    return this.paramQuery(q, [configuration, companyId])
  }

  public async addUsageRecord(
    description: string,
    localTime: string,
    userId: number
  ): Promise<void> {
    const { usageTracker } = db
    const q = `INSERT INTO ${usageTracker.tableName}(${usageTracker.description}, 
    ${usageTracker.userId}, ${usageTracker.usersLocalTime}) VALUES ($1, $2, $3);`
    this.paramQuery(q, [description, userId, localTime])
  }

  public async getCompanyManagers(companyId: number): Promise<object[]> {
    const { id, isDeleted, manager, name, tableName } = db.userTable
    const q = `SELECT ${id}, ${name} FROM ${tableName} WHERE ${id} IN 
    (SELECT DISTINCT ${manager} FROM ${tableName} WHERE 
    ${db.userTable.companyId} = $1 AND ${isDeleted} = false);`

    return this.paramQuery(q, [companyId])
  }

  public async addNewUser(
    accountType: string,
    companyId: number,
    crmId: string,
    email: string,
    fullName: string,
    managerId: number,
    jobTitle: string,
    metricProfileId: number,
    startDate: string
  ): Promise<number> {
    const { userTable } = db
    const { crmID, manager, name, tableName, id } = userTable
    const q = `INSERT INTO ${tableName}(${userTable.accountType}, 
    ${userTable.companyId}, ${crmID}, ${userTable.email}, ${name}, ${manager}, 
    ${userTable.role}, ${userTable.metricProfileId}, ${userTable.startDate}) 
    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING ${id};`
    const result = await this.paramQuery(q, [
      accountType,
      companyId,
      crmId,
      email,
      fullName,
      managerId,
      jobTitle,
      metricProfileId,
      startDate
    ])
    return result && result[0] && result[0][id] ? result[0][id] : null
  }

  public async updateUser(userId: number, params: object): Promise<boolean> {
    const {
      accountType,
      crmID,
      email,
      id,
      name,
      manager,
      metricProfileId,
      startDate,
      tableName
    } = db.userTable

    const paramToField = {
      accountType,
      crmId: crmID,
      email,
      fullName: name,
      managerId: manager,
      metricProfileId,
      jobTitle: 'role',
      startDate
    }

    const setValues = []
    const setString = Object.keys(paramToField)
      .reduce((previousValue, value) => {
        if (Object.prototype.hasOwnProperty.call(params, value)) {
          setValues.push(params[value])
          return `${previousValue} ${paramToField[value]} = $${setValues.length},`
        }
        return previousValue
      }, 'SET')
      .slice(0, -1)

    const q = `UPDATE ${tableName} ${setString} WHERE ${id} = 
    $${setValues.length + 1};`
    return this.paramQuery(q, [...setValues, userId])
  }

  public async deleteUser(
    companyId: number,
    userId: number,
    newManagerId: number,
    userIds: number[]
  ): Promise<boolean> {
    const { tableName, isDeleted, id } = db.userTable
    const q = `UPDATE ${tableName} SET ${isDeleted} = true WHERE ${db.userTable.companyId} = $1 AND ${id} = $2;`

    if (newManagerId) {
      await this.changeManager(newManagerId, userIds)
    }

    return this.paramQuery(q, [companyId, userId])
  }

  public async changeManager(
    newManagerId: number,
    userIds: number[]
  ): Promise<boolean> {
    const { id, manager, tableName } = db.userTable
    const q = `UPDATE ${tableName} SET ${manager} = $1 WHERE ${id} IN 
    ${this.parameterizeIdsForQuery(userIds, 1)};`

    return this.paramQuery(q, [newManagerId, userIds.toString()])
  }

  public async reenableUser(
    companyId: number,
    userId: number
  ): Promise<boolean> {
    const { userTable } = db
    const q = `UPDATE ${userTable.tableName} SET ${userTable.isDeleted} =
    false WHERE ${userTable.companyId} = $1 AND ${userTable.id} = $2;`
    return this.paramQuery(q, [companyId, userId])
  }

  public async getConfigurationByUserId(userId: number): Promise<object[]> {
    const { companyTable, userTable } = db
    const q = `SELECT ${companyTable.configuration} FROM ${companyTable.tableName} WHERE ${companyTable.id} IN 
    (SELECT ${userTable.companyId} FROM ${userTable.tableName} WHERE ${userTable.id} = $1 LIMIT 1);`
    return this.paramQuery(q, [userId])
  }

  public async logLoginAttempt(id: number): Promise<void> {
    const { loginActivity } = db
    const q = `INSERT INTO ${db.loginActivity.tableName} 
    (${loginActivity.timestamp}, ${loginActivity.userId}) VALUES ($1, $2);`
    return this.paramQuery(q, [new Date().toISOString(), id])
  }

  public async setUserProfilePicture(
    imageId: number,
    userId: number
  ): Promise<void> {
    const { userTable } = db
    const q = `UPDATE ${userTable.tableName} SET ${userTable.imageId} = $1 WHERE
     ${userTable.id} = $2;`
    this.paramQuery(q, [imageId, userId])
  }

  public async addProfilePicture(image: {
    name: string
    ext: string
    size: number
    type: string
  }): Promise<number> {
    const { imagesTable } = db

    const query = `INSERT INTO ${imagesTable.tableName} (${imagesTable.name}, 
    ${imagesTable.ext}, ${imagesTable.size}, ${imagesTable.type}) VALUES 
    ($1, $2, $3, $4) RETURNING ${imagesTable.id};`

    const imageCreated = await this.paramQuery(query, [
      image.name,
      image.ext,
      image.size,
      image.type
    ])
    return (imageCreated[0] && imageCreated[0][imagesTable.id]) || null
  }

  public async getProfilePictureByUserId(userId: number): Promise<IImage> {
    const { imagesTable, userTable } = db

    const q = `SELECT ${imagesTable.tableName}.* FROM ${userTable.tableName} 
    INNER JOIN ${imagesTable.tableName} ON ${userTable.tableName}.${userTable.imageId} =
    ${imagesTable.tableName}.${imagesTable.id} WHERE  ${userTable.tableName}.${userTable.id} = $1;`

    const image = await this.paramQuery(q, [userId])
    return (image && image[0]) || null
  }

  public async logInteraction(
    createdById: number,
    ownerId: number,
    message: string
  ): Promise<IInteraction[]> {
    const { interactions } = db
    const q = `INSERT INTO ${interactions.tableName} (
    ${interactions.ownerId}, ${interactions.createdById},
    ${interactions.message}, ${interactions.dateTime}) VALUES
    ($1, $2, $3, $4) RETURNING
    ${interactions.ownerId}, ${interactions.createdById},
    ${interactions.message}, ${interactions.dateTime};`
    return this.paramQuery(q, [
      ownerId,
      createdById,
      message,
      new Date().getTime()
    ])
  }

  public async getSkillsOfRolesByCompanyIdOrderByStageIndex(
    companyId: number,
    columns?: string[]
  ): Promise<APISalesProcessSkill[]> {
    const { skillsTable, rolesTable } = db
    const query = `SELECT ${this.includeColumns(columns, skillsTable)} FROM 
    ${skillsTable.tableName} WHERE ${skillsTable.roleId} IN 
    (SELECT ${rolesTable.id} FROM ${rolesTable.tableName} WHERE 
    ${rolesTable.companyId} = $1) ORDER BY ${skillsTable.stageIndex} ASC;`

    const skills: APISalesProcessSkill[] = await this.paramQuery(query, [
      companyId
    ])

    return skills.map(
      (object: APISalesProcessSkill): APISalesProcessSkill =>
        StringManipulator.convertObjectPropertiesToCamelCase(object)
    )
  }

  public async getDesiredBehaviorsOfRolesByCompanyId(
    companyId: number,
    columns?: string[]
  ): Promise<APIMeasurableWorkDesiredBehavior[]> {
    const { desiredBehaviorsTable, rolesTable } = db
    const query = `SELECT ${this.includeColumns(
      columns,
      desiredBehaviorsTable
    )} FROM
    ${desiredBehaviorsTable.tableName} WHERE ${desiredBehaviorsTable.roleId} IN 
    (SELECT ${rolesTable.id} FROM ${rolesTable.tableName} WHERE ${
      rolesTable.companyId
    } = $1);`

    const desiredBehaviors: APIMeasurableWorkDesiredBehavior[] = await this.paramQuery(
      query,
      [companyId]
    )

    return desiredBehaviors.map(
      (
        object: APIMeasurableWorkDesiredBehavior
      ): APIMeasurableWorkDesiredBehavior =>
        StringManipulator.convertObjectPropertiesToCamelCase(object)
    )
  }

  private includeColumns(
    columns: string[],
    databaseTable: { [key: string]: string }
  ): string {
    if (!columns) {
      return '*'
    }

    let selected = ''
    const lastIndex = columns.length - 1

    for (let i = 0; i < columns.length; ++i) {
      const columnName = columns[i]
      this.validateColumnIfPropertyOfTable(columnName, databaseTable)

      selected += columnName
      if (i !== lastIndex) {
        selected += ', '
      }
    }

    selected += ' '
    return selected
  }

  private validateColumnIfPropertyOfTable = (
    columnName: string,
    databaseTable: { [key: string]: string }
  ): void => {
    if (!Object.values(databaseTable).includes(columnName)) {
      const invalidDatabaseColumnCode = 1042
      const errorMessage = `${errorCodes[invalidDatabaseColumnCode]} ${columnName} on table ${databaseTable.tableName}`
      throw new Error(errorMessage)
    }
  }

  public async getActivity(): Promise<IActivity[]> {
    const { activityView, userTable } = db
    const query = `SELECT * FROM ${activityView.viewName} WHERE
    ${activityView.utcTime} > now() - interval '48 hours' AND ${activityView.userId} IN (
     SELECT ${userTable.id} FROM ${userTable.tableName} WHERE ${userTable.companyId} != 3 
     OR ${userTable.role} = 'databased admin' or ${userTable.role} = 'Databased admin')
     AND ${activityView.fullName} != 'databased admin' 
    AND ${activityView.fullName} != 'Databased admin' 
    AND ${activityView.fullName} != 'DataBased Admin' 
    AND ${activityView.fullName} != 'Databased Admin'`
    return this.paramQuery(query, [])
  }

  public async getLoggedInHistory(): Promise<ILoggedInHistory[]> {
    const { loggedInHistoryView, userTable } = db
    const query = `SELECT * FROM ${loggedInHistoryView.viewName} WHERE
    ${loggedInHistoryView.fullName} NOT IN (
    SELECT ${userTable.name} FROM ${userTable.tableName} WHERE 
    (${userTable.companyId} = $1 OR ${userTable.companyId} = $2)) AND
    ${userTable.name} != $3 AND
    ${userTable.name} != $4 AND
    ${userTable.name} != $5 AND
    ${userTable.name} != $6 AND
    ${loggedInHistoryView.timestamp} > now() - interval '48 hours';`
    return this.paramQuery(query, [
      3,
      107,
      'Databased admin',
      'databased admin',
      'Databased Admin',
      'DataBased Admin'
    ])
  }

  public async getCompanyCRMTypeByUserId(id: number): Promise<string> {
    const { companyTable, userTable } = db
    const q = `SELECT ${companyTable.crmType} FROM ${companyTable.tableName} WHERE 
    ${companyTable.id} IN 
    (SELECT ${userTable.companyId} FROM ${userTable.tableName} WHERE ${userTable.id} = $1);`
    const result = await this.paramQuery(q, [id])
    return result[0] && result[0][companyTable.crmType]
      ? result[0][companyTable.crmType]
      : null
  }

  public async doesUserBelongToCompany(
    companyId: number,
    userId: number
  ): Promise<boolean> {
    const userCompanyId = await this.getCompanyId(userId)
    return userCompanyId === companyId
  }

  public async getCompanyId(userId: number): Promise<number> {
    const {
      userTable: { tableName, companyId, id }
    } = descriptors
    const res = await this.paramQuery(
      `SELECT ${companyId} FROM ${tableName} WHERE ${id} = $1;`,
      [userId]
    )

    if (res && res[0]) {
      return res[0][companyId]
    }
    return null
  }

  public async getConfigurationByMetricIds(
    ids: number[]
  ): Promise<IQuadrantMetric[]> {
    const { tableName, metricId } = descriptors.quadrantMetrics
    const query = `SELECT * FROM ${tableName} WHERE ${metricId} IN (${this.expandParamList(
      ids
    )});`
    return this.paramQuery(query, ids)
  }

  public expandParamList(params: any[]): string {
    return params.reduce((previous, current, index) => {
      if (!index) {
        return `$${++index}`
      }
      return `${previous},$${++index}`
    }, '')
  }

  public async postQuadrantConfig(
    metrics: APIQuadrantMetric[],
    connection?: pg
  ): Promise<APIStatus> {
    if (metrics.length === 0) {
      return General.buildAPIStatus(okHttpCode, '')
    }

    const {
      tableName,
      metricId,
      axis,
      maxCredit,
      numTargetPeriods,
      rollingWorkdays,
      weight
    } = descriptors.quadrantMetrics
    const values = []
    let baseQuery = `INSERT INTO ${tableName} (${axis}, ${maxCredit}, ${metricId}, ${numTargetPeriods}, ${weight}, ${rollingWorkdays}) VALUES `
    let iter = 0
    const finalQuery = metrics.reduce((query, metric, idx) => {
      values.push(
        metric.axis,
        metric.maxCredit,
        metric.metricId,
        metric.numTargetPeriods,
        metric.weight,
        metric.rollingWorkdays
      )
      const value = `($${++iter}, $${++iter}, $${++iter}, $${++iter}, $${++iter}, $${++iter})`
      return query + value + (idx === metrics.length - 1 ? ';' : ',')
    }, baseQuery)

    let result = null
    if (connection) {
      result = await this.paramQueryWithCustomConnection(
        finalQuery,
        values,
        connection
      )
    } else {
      result = await this.paramQuery(finalQuery, values)
    }

    return result === null
      ? General.buildAPIStatus(
          internalServerError,
          'Unable to persist configuration, try again later'
        )
      : General.buildAPIStatus(okHttpCode, '')
  }

  public async updateQuadrantConfig(
    metrics: APIQuadrantMetric[],
    metricIds: number[]
  ): Promise<APIStatus> {
    const connection = await this.openConnection()
    await this.beginTransactionWithConnection(connection)
    const deleteStatus = await this.deleteQuadrantConfigurationByMetricProfileId(
      metricIds,
      connection
    )

    if (deleteStatus.code !== okHttpCode) {
      await this.commitTransactionWithConnection(false, connection)
      return deleteStatus
    }
    const postStatus = await this.postQuadrantConfig(metrics, connection)

    if (postStatus.code !== okHttpCode) {
      await this.commitTransactionWithConnection(false, connection)
    } else {
      await this.commitTransactionWithConnection(true, connection)
    }
    return postStatus
  }

  public async deleteQuadrantConfigurationByMetricProfileId(
    metricIds: number[],
    connection?: pg
  ): Promise<APIStatus> {
    const { tableName, metricId } = descriptors.quadrantMetrics
    const query = `DELETE FROM ${tableName} WHERE ${metricId} IN (${this.expandParamList(
      metricIds
    )});`

    let result = null
    if (connection) {
      result = await this.paramQueryWithCustomConnection(
        query,
        metricIds,
        connection
      )
    } else {
      result = await this.paramQuery(query, metricIds)
    }

    return result === null
      ? General.buildAPIStatus(
          internalServerError,
          'Unable to delete configuration, please try again later'
        )
      : General.buildAPIStatus(okHttpCode, '')
  }

  public async getAdminIdForCompany(
    requestedCompanyId: number
  ): Promise<number> {
    const { tableName, id, companyId, accountType } = db.userTable
    const q = `SELECT ${id} FROM ${tableName} WHERE ${companyId} = $1 AND ${accountType} = 'admin' LIMIT 1;`
    const res = await this.paramQuery(q, [requestedCompanyId])

    return res && res[0] && res[0][id] ? res[0][id] : null
  }

  public async getUsernamesByIds(
    ids: number[]
  ): Promise<{ full_name: string }[]> {
    const { tableName, id, name } = db.userTable
    const query = `SELECT ${name} FROM ${tableName} WHERE ${id} IN 
    (${this.expandParamList(ids)});`
    return this.paramQuery(query, ids)
  }
}

export default PersistenceManager
