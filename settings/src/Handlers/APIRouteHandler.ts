import express from 'express'
import * as aws from 'aws-sdk'
import fs from 'fs'
import req from 'request'
import APIHomeData from '../API/APIHomeData'
import APIImpactReport from '../API/APIImpactReport'
import APIInteraction from '../API/APIInteraction'
import APIManagerReport from '../API/APIManagerReport'
import APIMeasurableWorkDesiredBehavior from '../API/APIMeasurableWorkDesiredBehavior'
import APIMetric from '../API/APIMetric'
import APIMetricRole from '../API/APIMetricRole'
import APIOnboardData from '../API/APIOnboardData'
import APIQuadrantData from '../API/APIQuadrantData'
import APIQuadrantStats from '../API/APIQuadrantStats'
import APIRole from '../API/APIRole'
import APISalesProcessSkill from '../API/APISalesProcessSkill'
import APISkill from '../API/APISkill'
import APITeam from '../API/APITeam'
import APITeamMember from '../API/APITeamMember'
import DateHelper from '../Utilities/DateHelper'
import descriptors from '../PersistenceManager/DatabaseDescriptors'
import errorCodes from '../ErrorCodes'
import IAPIPersistenceManager from './Interfaces/IAPIPersistenceManager'
import IAuthorizer from '../Authorizer/IAuthorizer'
import ICurrentManagerInteractions from './Interfaces/ICurrentManagerInteractions'
import IDBTraining from '../DBTableInterfaces/IDBTraining'
import IDecodedAuthToken from '../Authorizer/IDecodedAuthToken'
import IDesiredBehavior from '../DBTableInterfaces/IDesiredBehavior'
import IImpactReport from '../DBTableInterfaces/IImpactReport'
import IInteraction from '../DBTableInterfaces/IInteraction'
import IFacadeImpact from '../Impact/InterfacesImpact/IFacadeImpact'
import IFileMulter from './Interfaces/IFileMulter'
import ISFOAuthInfo from '../DBTableInterfaces/ISFOAuthInfo'
import ITerm from '../MetricsAPI/Interfaces/ITerm'
import ITraining from './Interfaces/ITraining'
import IUser from '../DBTableInterfaces/IUser'
import Logger from '../Logger/Logger'
import Mailer from './Mailer'
import MetricsAPI from '../MetricsAPI/MetricsAPI'
import Onboard from '../Onboarding/Onboard'
import IManagerList from './Interfaces/IManagerList'
import IManagerInteraction from './Interfaces/IManagerInteraction'
import IPreviousManagerInteractions from './Interfaces/IPreviousManagerInteractions'
import IScorecardSkillsDTO from '../DBTableInterfaces/IScorecardSkillsDTO'
import IScorecardMetricDTO from './Interfaces/IScorecardMetricDTO'
import SalesProcessAnalysisHandler from './SalesProcessAnalysis/SalesProcessAnalysisHandler'
import StringManipulator from '../Utilities/StringManipulator'

const OK = 200
const NOT_FOUND = 404

class APIRouteHandler {
  private authorizer: IAuthorizer
  private pm: IAPIPersistenceManager
  private db: any = descriptors
  private s3: any

  constructor(
    authorizer: IAuthorizer,
    persistenceManager: IAPIPersistenceManager
  ) {
    this.authorizer = authorizer
    this.pm = persistenceManager
    aws.config.update({
      accessKeyId: process.env.AWS_ACCESS_KEY,
      secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY
    })
    this.s3 = new aws.S3()
  }

  public error(code: number): { code: number; error: string } {
    return {
      code,
      error: errorCodes[code]
    }
  }

  public async createAccount(
    fullName: string,
    email: string,
    password: string,
    companyName: string
  ): Promise<object> {
    const onboarder = new Onboard()
    const responseCode = await onboarder.createAccount(
      fullName,
      email,
      password,
      companyName
    )
    if (responseCode === OK) {
      return {
        message: 'Your account was successfully created'
      }
    }
    return {
      code: responseCode,
      error: errorCodes[responseCode]
    }
  }

  public async getTags(token: string): Promise<object> {
    const decodedAuth: IDecodedAuthToken = this.authorizer.decodeAuthToken(
      token
    )
    if (decodedAuth) {
      const tagObjects: object[] = await this.pm.getCompanyTagsByUserId(
        decodedAuth.userId
      )
      const tagArr = tagObjects.map(tag => {
        const key = Object.keys(tag)[0]
        return tag[key]
      })
      return { tags: tagArr }
    }
    const code = 1003
    return {
      code,
      error: errorCodes[code]
    }
  }

  public async getUserImpactReport(
    impactFacade: IFacadeImpact,
    token: string,
    personId: number
  ): Promise<object> {
    const decodedAuth: IDecodedAuthToken = this.authorizer.decodeAuthToken(
      token
    )
    if (decodedAuth) {
      try {
        const ir = await this.pm.getUserImpactReportByOwnerId(personId)
        if (ir !== null && ir[this.db.impactReportTable.winSkills]) {
          const apiImpactReport: APIImpactReport[] = []
          const skills = JSON.parse(ir[this.db.impactReportTable.winSkills])
          skills.forEach(rep => {
            if (rep.trainingScore > 0) {
              apiImpactReport.push({
                displayName: rep.displayName,
                outcomeIncrease: rep.impactIncrease,
                performance: parseFloat(rep.performance),
                benchmark: parseFloat(rep.benchmark),
                unit: rep.unit,
                skillId: rep.id,
                outcomeUnit: rep.outcomeUnit,
                message: rep.message
              })
            }
          })
          const name: string = await this.pm.getUserNameById(personId)
          return {
            report: {
              personId,
              name,
              skills: apiImpactReport
            }
          }
        }
        return { code: 1033, error: errorCodes[1033] }
      } catch (err) {
        Logger.info(
          `ERROR: APIRouteHandler.ts->getUserImpactReport ${err}`,
          'err'
        )
      }
    }
    const code = 1003
    return { code, error: errorCodes[code] }
  }

  private userIsAdmin(userId: number): Promise<boolean> {
    return this.pm.isAdmin(userId)
  }

  private async userIsManagerOrAdmin(userId: number): Promise<boolean> {
    return (
      (await this.userIsAdmin(userId)) || (await this.userIsManager(userId))
    )
  }

  private async userIsManager(userId: number): Promise<boolean> {
    const managers: number[] = await this.pm.getUsersManagedByUserId(userId)
    if (managers === null) {
      return false
    }
    return managers.length > 0
  }

  public async forgotPassword(email: string): Promise<void> {
    const user = await this.pm.emailExists(email)
    if (user) {
      Mailer.sendResetLink(
        email,
        user[this.db.userTable.name],
        user[this.db.userTable.id]
      )
    }
  }

  private async getCompanyUsers(userId: number): Promise<IUser[]> {
    const companyId: number = await this.pm.getCompanyIdFromUserId(userId)
    if (companyId) {
      return this.pm.getUsersByCompanyId(companyId)
    }
    return null
  }

  public async getUserManagementData(token: string): Promise<object> {
    const decodedAuth: IDecodedAuthToken = this.authorizer.decodeAuthToken(
      token
    )
    const unauthorizedCode = 1003
    const couldNotGetUsersCode = 1048

    if (!decodedAuth) {
      return this.error(unauthorizedCode)
    }

    const {
      accountType,
      crmID,
      email,
      id,
      manager,
      metricProfileId,
      name,
      startDate
    } = this.db.userTable
    const companyId: number = await this.pm.getCompanyIdFromUserId(
      decodedAuth.userId
    )
    const managers = (await this.pm.getCompanyManagers(companyId)).map(
      (manager: any) => ({
        id: manager[id],
        name: manager[name]
      })
    )

    const unsortedUsers = (await this.pm.getUsersByCompanyId(companyId)).filter(
      user =>
        user &&
        Object.prototype.hasOwnProperty.call(user, 'account_type') &&
        user.account_type !== 'db-admin'
    )
    const metricProfiles = await MetricsAPI.getMetricProfilesByAuthToken(token)

    const users = []
    for (let i = 0; i < unsortedUsers.length; i++) {
      const user = unsortedUsers[i]
      const metricProfileName = metricProfiles.find(
        profile => profile.id === user[metricProfileId]
      )
      users.push({
        accountType: user[accountType],
        crmId: user[crmID],
        email: user[email],
        fullName: user[name],
        id: user[id],
        jobTitle: user.role || '',
        managerId: user[manager] || -1,
        metricProfileId: user[metricProfileId] || -1,
        metricProfileName: metricProfileName ? metricProfileName.name : '',
        startDate: user[startDate] ? user[startDate].toString() : ''
      })
    }

    if (users) {
      return { users, managers }
    }
    return this.error(couldNotGetUsersCode)
  }

  public async getUsers(token: string): Promise<object> {
    const decodedAuth: IDecodedAuthToken = this.authorizer.decodeAuthToken(
      token
    )
    const unauthorizedCode = 1003
    const couldNotGetUsersCode = 1048
    const mustBeAdminCode = 1049

    if (decodedAuth) {
      const userIsAManagerOrAdmin = await this.userIsManagerOrAdmin(
        decodedAuth.userId
      )

      if (!userIsAManagerOrAdmin) {
        return this.error(mustBeAdminCode)
      }

      const {
        accountType,
        crmID,
        id,
        name,
        role,
        roleId,
        startDate
      } = this.db.userTable
      const users = (await this.getCompanyUsers(decodedAuth.userId))
        .filter(
          user =>
            user &&
            Object.prototype.hasOwnProperty.call(user, 'account_type') &&
            user.account_type !== 'db-admin'
        )
        .map(user => ({
          accountType: user[accountType],
          crmId: user[crmID],
          id: user[id],
          fullName: user[name],
          role: user[role],
          roleId: user[roleId] || -1,
          startDate: user[startDate] ? user[startDate].toString() : ''
        }))
      if (users) {
        return { users }
      }
      return this.error(couldNotGetUsersCode)
    }

    return this.error(unauthorizedCode)
  }

  public async addUser(
    token: string,
    request: express.Request
  ): Promise<object> {
    const decodedAuth: IDecodedAuthToken = this.authorizer.decodeAuthToken(
      token
    )
    const isAdmin = await this.userIsAdmin(decodedAuth.userId)
    const badDataCode = 1032
    const mustBeAdminCode = 1049
    const mustBeAdminToAddUserCode = 1051

    if (decodedAuth) {
      const userIsAManagerOrAdmin = await this.userIsManagerOrAdmin(
        decodedAuth.userId
      )

      if (!userIsAManagerOrAdmin) {
        return this.error(mustBeAdminCode)
      }

      if (request.body.accountType === 'admin' && !isAdmin) {
        return this.error(mustBeAdminToAddUserCode)
      }

      const companyId = await this.pm.getCompanyIdFromUserId(decodedAuth.userId)
      const newUserId = await this.pm.addNewUser(
        request.body.accountType,
        companyId,
        request.body.crmId,
        request.body.email,
        request.body.fullName,
        request.body.managerId,
        request.body.jobTitle,
        request.body.metricProfileId || null,
        request.body.startDate
      )

      if (newUserId) {
        if (request.body.notifyUser) {
          Mailer.sendVerificationEmail(
            request.body.email,
            request.body.fullName,
            newUserId
          )
        }

        return {
          message: 'Added new user successfully!'
        }
      }

      return this.error(badDataCode)
    }
  }

  public async getCanModifyUserError(
    decodedAuth,
    req: express.Request,
    usersManagedByUser: number[],
    deletingManager = false
  ): Promise<any> {
    const mustBeAdminCode = 1049
    const mustManageCode = 1054
    const needNewManagerIdCode = 1055

    const usersManagedByLoggedInUser = await this.pm.getAllUsersManagedByUserId(
      decodedAuth.userId
    )
    const loggedInUserIsAdmin = await this.userIsAdmin(decodedAuth.userId)
    const loggedInUserIsManager = !!usersManagedByLoggedInUser.length

    const userIsAdmin = await this.userIsAdmin(req.body.userId)
    const userIsManager = !!usersManagedByUser.length

    if (
      (userIsAdmin && !loggedInUserIsAdmin) ||
      (Object.prototype.hasOwnProperty.call(req.body, 'accountType') &&
        !loggedInUserIsAdmin)
    ) {
      return this.error(mustBeAdminCode)
    }

    if (
      loggedInUserIsManager &&
      !loggedInUserIsAdmin &&
      !usersManagedByLoggedInUser.includes(req.body.userId)
    ) {
      return this.error(mustManageCode)
    }

    if (
      deletingManager &&
      userIsManager &&
      !Object.prototype.hasOwnProperty.call(req.body, 'newManagerId')
    ) {
      return this.error(needNewManagerIdCode)
    }

    return null
  }

  public async updateUser(
    token: string,
    req: express.Request
  ): Promise<object> {
    const decodedAuth: IDecodedAuthToken = this.authorizer.decodeAuthToken(
      token
    )

    if (!decodedAuth) {
      const invalidAuthTokenCode = 1003
      return this.error(invalidAuthTokenCode)
    }

    const usersManagedByUser = await this.pm.getUsersManagedByUserId(
      req.body.userId
    )
    const error = await this.getCanModifyUserError(
      decodedAuth,
      req,
      usersManagedByUser
    )

    if (error) {
      return error
    }

    const unableCode = 1053
    const updatedUser = await this.pm.updateUser(req.body.userId, req.body)

    if (updatedUser) {
      return {
        message: 'Updated user successfully!'
      }
    }

    return this.error(unableCode)
  }

  public async deleteUser(token: string, req: express.Request): Promise<any> {
    const decodedAuth: IDecodedAuthToken = this.authorizer.decodeAuthToken(
      token
    )

    if (!decodedAuth) {
      const invalidAuthTokenCode = 1003
      return this.error(invalidAuthTokenCode)
    }

    const usersManagedByUser = await this.pm.getUsersManagedByUserId(
      req.body.userId
    )
    const error = await this.getCanModifyUserError(
      decodedAuth,
      req,
      usersManagedByUser,
      true
    )
    if (error) {
      return error
    }

    const unableCode = 1056
    const companyId = await this.pm.getCompanyIdFromUserId(decodedAuth.userId)

    const deletedUser = await this.pm.deleteUser(
      companyId,
      req.body.userId,
      req.body.newManagerId || null,
      usersManagedByUser
    )

    if (deletedUser) {
      return {
        message: 'Deleted user successfully!'
      }
    }
    return this.error(unableCode)
  }

  public async reenableUser(token: string, req: express.Request): Promise<any> {
    const decodedAuth: IDecodedAuthToken = this.authorizer.decodeAuthToken(
      token
    )

    const mustBeAdminCode = 1053
    const unableCode = 1056
    const invalidAuthTokenCode = 1003

    if (!decodedAuth) {
      return this.error(invalidAuthTokenCode)
    }

    const companyId = await this.pm.getCompanyIdFromUserId(decodedAuth.userId)
    const loggedInUserIsAdmin = await this.userIsAdmin(decodedAuth.userId)
    const userIsAdmin = await this.userIsAdmin(req.body.userId)

    if (userIsAdmin && !loggedInUserIsAdmin) {
      return this.error(mustBeAdminCode)
    }

    const enabledUser = await this.pm.reenableUser(companyId, req.body.userId)

    if (enabledUser) {
      return {
        message: 'Reenabled user successfully!'
      }
    }

    return this.error(unableCode)
  }

  public async getConfiguration(token: string): Promise<object> {
    const decodedAuth: IDecodedAuthToken = this.authorizer.decodeAuthToken(
      token
    )
    if (decodedAuth) {
      const config = await this.pm.getConfigurationByUserId(decodedAuth.userId)
      if (config !== null && config[0] !== undefined) {
        return config[0]
      }
      const code = 2112
      return { code, error: errorCodes[code] }
    }
    const code = 1003
    return { code, error: errorCodes[code] }
  }

  private setPersonIdToManagerId(teams: APITeam[]): object {
    const map = {}
    teams.forEach(team => {
      map[team.manager.id] = team.manager.managerId
      team.members.forEach(member => {
        map[member.id] = member.managerId
      })
    })
    return map
  }

  private addUserStartDate(
    impactReport: IImpactReport[],
    userIdStartDates: { id: number; start_date: string }[]
  ): void {
    userIdStartDates.forEach(user => {
      const today = new Date()
      const workDaysIntoJob = DateHelper.numberBusinessDaysInDateRangeInclusive(
        new Date(user.start_date),
        new Date(today.setDate(today.getUTCDate() - 1))
      )
      if (workDaysIntoJob < DateHelper.workDaysInQuarter) {
        const ir = impactReport.find(report => report.owner_id === user.id)
        if (ir) {
          ir.workDaysIntoJob = workDaysIntoJob
        }
      }
    })
  }

  private async getHomeDataForUser(userId: number): Promise<APIHomeData> {
    try {
      let impactReports = await this.pm.getImpactReportsByUserId(userId)
      const companyId: number = await this.pm.getCompanyIdFromUserId(userId)
      const userIdStartDates: {
        id: number
        start_date: string
      }[] = await this.pm.getUsersStartDateByCompanyId(companyId)
      const teams: APITeam[] = await this.pm.getTeams(companyId)
      const personIdToManagerId: object = this.setPersonIdToManagerId(teams)
      const teamMembers: APITeamMember[] = this.getTeamFromCompanyTeamsByManagerId(
        userId,
        teams
      )

      impactReports = this.filterReportNonZeroInsights(impactReports)
      this.addUserStartDate(impactReports, userIdStartDates)
      const coordinates: APIQuadrantData[] = await this.pm.getQuadrantData(
        companyId
      )

      return {
        report: this.getReport(
          impactReports,
          teamMembers,
          teams,
          personIdToManagerId
        ),
        quadrantData: coordinates,
        teams,
        roleIdToTimePeriod: await this.getRoleIdToTimePeriod(companyId)
      }
    } catch (err) {
      Logger.info(
        `APIRouteHandler.ts -> getHomeDataForManager(). err ${err}`,
        'err'
      )
    }
    return null
  }

  private async getRoleIdToTimePeriod(companyId: number): Promise<object> {
    const { id, frequency } = descriptors.rolesTable
    const results = await this.pm.getRolesByCompanyId(companyId)
    return results.reduce((map, res) => {
      map[res[id]] = res[frequency]
      return map
    }, {})
  }

  private getCoordinatesForTeam(
    coordinates: APIQuadrantData[],
    teams: APITeamMember[],
    companyTeam: APITeam[]
  ): APIQuadrantData[] {
    const coords = coordinates.filter(
      coordinate =>
        teams.filter(teamMember => teamMember.id === coordinate.personId).length
    )
    return coords.length
      ? coords
      : this.recurseTeamTree(coordinates, teams, companyTeam)
  }

  private recurseTeamTree(
    coordinates: APIQuadrantData[],
    teams: APITeamMember[],
    companyTeam: APITeam[]
  ): APIQuadrantData[] {
    const newTeams = this.getUsersFromTeamByManagers(teams, companyTeam)
    return newTeams.length
      ? this.getCoordinatesForTeam(coordinates, newTeams, companyTeam)
      : []
  }

  private getUsersFromTeamByManagers(
    teamMembers: APITeamMember[],
    companyTeam: APITeam[]
  ): APITeamMember[] {
    let newTeams: APITeamMember[] = []
    teamMembers.forEach(teamMember => {
      companyTeam.forEach(team => {
        if (teamMember.id === team.manager.id) {
          newTeams = newTeams.concat(team.members)
        }
      })
    })
    return newTeams
  }

  private filterReportNonZeroInsights(
    reports: IImpactReport[]
  ): IImpactReport[] {
    const newReports = [...reports]
    for (let i = 0; i < reports.length; i++) {
      newReports[i].win_skills = JSON.stringify(
        JSON.parse(reports[i].win_skills).filter(x => {
          return (
            x.impactIncrease > 0 || (x.message !== '' && x.message !== null)
          )
        })
      )
    }
    return newReports
  }

  private getReport(
    impactReports: IImpactReport[],
    team: APITeamMember[],
    companyTeams: APITeam[],
    personIdToManagerId: object
  ): APIManagerReport[] {
    const report: APIManagerReport[] = []

    for (let i = 0; i < impactReports.length; i++) {
      const skills = JSON.parse(impactReports[i].win_skills)
      const apiImpactReports: APIImpactReport[] = []
      const name =
        this.getEmployeeNameFromTeam(team, impactReports[i].owner_id) ||
        this.getEmployeeNameFromCompany(impactReports[i].owner_id, companyTeams)

      skills.forEach(skill => {
        apiImpactReports.unshift({
          displayName: skill.displayName,
          outcomeIncrease: skill.impactIncrease,
          performance: parseFloat(skill.performance),
          benchmark: parseFloat(skill.benchmark),
          unit: skill.unit,
          skillId: skill.id,
          outcomeUnit: skill.outcomeUnit,
          message: skill.message
        })
      })

      report.push({
        name,
        personId: impactReports[i].owner_id,
        skills: apiImpactReports,
        managerId: personIdToManagerId[impactReports[i].owner_id],
        workDaysIntoJob:
          impactReports[i].workDaysIntoJob || DateHelper.workDaysInQuarter
      })
    }
    return report
  }

  private getEmployeeNameFromCompany(
    userId: number,
    companyTeams: APITeam[]
  ): string {
    let name = ''
    for (let i = 0; i < companyTeams.length; i++) {
      if (companyTeams[i].manager.id === userId) {
        name = companyTeams[i].manager.name
        break
      } else {
        for (let j = 0; j < companyTeams[i].members.length; j++) {
          if (companyTeams[i].members[j].id === userId) {
            name = companyTeams[i].members[j].name
            break
          }
        }
      }
    }
    return name
  }

  private getTeamFromCompanyTeamsByManagerId(
    managerId: number,
    teams: APITeam[]
  ): APITeamMember[] {
    for (let i = 0; i < teams.length; i++) {
      if (teams[i].manager.id === managerId) {
        return teams[i].members
      }
    }
    return null
  }

  private getEmployeeNameFromTeam(
    team: APITeamMember[],
    ownerId: number
  ): string {
    if (team) {
      for (let i = 0; i < team.length; i++) {
        if (team[i].id === ownerId) {
          return team[i].name
        }
      }
    }
    return ''
  }

  public async getHomeData(authToken: string): Promise<any> {
    const decodedAuthToken: IDecodedAuthToken = this.authorizer.decodeAuthToken(
      authToken
    )
    if (decodedAuthToken) {
      return this.getHomeDataForUser(decodedAuthToken.userId)
    }
    const code = 1003
    return { error: errorCodes[code], code }
  }

  public async getScorecardMetrics(
    adjustedTargetsForTimePeriod: IDesiredBehavior[],
    personId: number,
    startDate: string,
    endDate: string
  ): Promise<IScorecardMetricDTO[]> {
    return Promise.all(
      adjustedTargetsForTimePeriod.map(async desiredBehavior => {
        return {
          unit: '',
          id: desiredBehavior.id,
          name: desiredBehavior.name,
          target: desiredBehavior.target,
          performance: await this.pm.getBehaviorPerformanceByDateRange(
            personId,
            desiredBehavior.id,
            startDate,
            endDate
          )
        }
      })
    )
  }

  private getQuarterTargetRatio(startDate: Date, endDate: Date): number {
    const workDaysBetweenDates = DateHelper.numberBusinessDaysInDateRangeInclusive(
      startDate,
      endDate
    )

    return workDaysBetweenDates / DateHelper.workDaysInQuarter
  }

  public adjustTargetsForTimePeriod(
    behaviors: IDesiredBehavior[],
    targetRatio: number
  ): IDesiredBehavior[] {
    return behaviors.map(desiredBehavior => {
      return {
        ...desiredBehavior,
        desiredBehaviorId: desiredBehavior.id,
        target: desiredBehavior.target * targetRatio
      }
    })
  }

  private changePerformancesBasedOnUnits(
    unsortedSkills: IScorecardSkillsDTO[],
    targetRatio: number
  ) {
    const skills = unsortedSkills.sort(
      (a: IScorecardSkillsDTO, b: IScorecardSkillsDTO) =>
        a.stage_index > b.stage_index ? 1 : -1
    )
    return skills.map(skill => {
      const previousSkill = skills.find(
        s => s.stage_index === skill.stage_index - 1
      )
      let performance = 0
      let target = parseInt(skill.benchmark, 10)
      if (skill.unit === '' || previousSkill === undefined) {
        performance = parseInt(skill.performance, 10)
        target = parseInt(skill.benchmark, 10) * targetRatio
      } else if (previousSkill && skill.unit === '%') {
        performance =
          (100 * parseInt(skill.performance, 10)) /
            parseInt(previousSkill.performance, 10) || 0
      } else if (skill.unit === '$') {
        performance =
          parseInt(skill.performance, 10) /
            parseInt(previousSkill.performance, 10) || 0
      }
      return {
        name: skill.user_facing_name,
        performance,
        sortOrder: skill.stage_index,
        target,
        unit: skill.unit
      }
    })
  }

  public async getScorecardData(
    authToken: string,
    userId: number,
    startDate: string,
    endDate: string
  ): Promise<any> {
    const decodedAuthToken: IDecodedAuthToken = this.authorizer.decodeAuthToken(
      authToken
    )

    if (decodedAuthToken) {
      try {
        const earliestPerformanceDate = DateHelper.getYYYY_MM_DDString(
          await this.pm.getUserStartDate(userId)
        )
        const skills: IScorecardSkillsDTO[] = await this.pm.getSkillsByDateRange(
          userId,
          startDate,
          endDate
        )
        const desiredBehaviors: IDesiredBehavior[] = await this.pm.getDesiredBehaviorTargetNameIdByUserId(
          userId
        )

        const targetRatio = this.getQuarterTargetRatio(
          new Date(startDate),
          new Date(endDate)
        )

        const scorecardMetrics: IScorecardMetricDTO[] = await this.getScorecardMetrics(
          this.adjustTargetsForTimePeriod(desiredBehaviors, targetRatio),
          userId,
          startDate,
          endDate
        )

        return {
          behaviors: scorecardMetrics.map(metric => {
            return {
              name: metric.name,
              performance: metric.performance,
              sortOrder: 0,
              target: metric.target,
              unit: ''
            }
          }),
          skills: this.changePerformancesBasedOnUnits(skills, targetRatio),
          earliestPerformanceDate
        }
      } catch (err) {
        Logger.info(
          `ERROR: APIRouteHandler.ts -> getScorecardData() err: ${err}`,
          'err'
        )
      }
    } else {
      const code = 1003
      return { code, error: errorCodes[code] }
    }
  }

  public async getPersonQuadrantStats(
    authToken: string,
    userId: number
  ): Promise<any> {
    const decodeAuthToken = this.authorizer.decodeAuthToken(authToken)
    if (
      decodeAuthToken !== null &&
      (await this.pm.getCompanyIdFromUserId(decodeAuthToken.userId)) ===
        (await this.pm.getCompanyIdFromUserId(userId))
    ) {
      try {
        const userStartDate: Date = await this.pm.getUserStartDate(userId)
        const daysPast = DateHelper.daysInMonth
        const metricProfileId = await this.pm.getMetricProfileIdByUserId(userId)
        const token = await MetricsAPI.generateAuthTokenForCommunicatingWithMetricsAPI(
          userId
        )
        let termsFromMetricsApi = await MetricsAPI.getTermsByMetricProfileId(
          token,
          metricProfileId
        )

        if (!(termsFromMetricsApi && termsFromMetricsApi.length)) {
          termsFromMetricsApi = []
        }
        termsFromMetricsApi.forEach(term => {
          term.type === 'expression' &&
            this.getExpressionCurrentStatus([term], termsFromMetricsApi)
        })

        const metricsFromMetricsApi = await MetricsAPI.getMetricsByMetricProfileId(
          token,
          metricProfileId
        )
        const quadStats: APIQuadrantStats = await this.pm.getPersonQuadrantStats(
          userId,
          metricsFromMetricsApi && metricsFromMetricsApi.length
            ? metricsFromMetricsApi
            : [],
          termsFromMetricsApi
        )
        const today = DateHelper.removeTimestampFromDate(new Date())
        const isNewHire: boolean = DateHelper.hasWorkedFewerDaysThanTimePeriod(
          userStartDate,
          today,
          daysPast
        )
        const actualWorkDaysForUser = DateHelper.numberBusinessDaysInDateRangeInclusive(
          userStartDate,
          new Date(today.setUTCDate(today.getUTCDate() - 1))
        )
        const workDaysIntoJob =
          actualWorkDaysForUser > DateHelper.workDaysInQuarter
            ? DateHelper.workDaysInQuarter
            : actualWorkDaysForUser

        const skills: APISkill[] = await SalesProcessAnalysisHandler.getSalesProcessMetrics(
          userId,
          this.pm
        )

        const canUseInteractions = await this.canUseInteractions(
          authToken,
          userId
        )
        const { xMetrics, yMetrics } = quadStats

        return {
          isNewHire,
          workDaysIntoJob,
          xMetrics,
          yMetrics,
          skills,
          canUseInteractions
        }
      } catch (err) {
        Logger.info(
          `ERROR: APIRouteHandler.ts -> getPersonQuadrantStats() err: ${err}`,
          'err'
        )
        const code = 1032
        return {
          code,
          error: errorCodes[code]
        }
      }
    } else {
      const code = 1003
      return { code, error: errorCodes[code] }
    }
  }

  private getExpressionCurrentStatus(
    expressions: ITerm[],
    terms: ITerm[],
    parentTerm?: ITerm
  ): void {
    expressions.forEach(expression => {
      const childTerms = [
        terms.find(t => t.id === expression.lh_term),
        terms.find(t => t.id === expression.rh_term)
      ].filter(term => term !== undefined)

      if (childTerms.some(term => term !== undefined)) {
        if (childTerms.some(term => term.type === 'expression')) {
          this.getExpressionCurrentStatus(
            childTerms.filter(term => term.type === 'expression'),
            terms,
            expression
          )
        } else {
          if (childTerms.some(term => term.isCurrentStatus === true)) {
            parentTerm
              ? (parentTerm.isCurrentStatus = true)
              : (expression.isCurrentStatus = true)
          } else {
            parentTerm
              ? (parentTerm.isCurrentStatus = false)
              : (expression.isCurrentStatus = false)
          }
        }
      }
    })
  }

  public async attemptLogin(
    email: string,
    password: string,
    res: express.Response
  ): Promise<void> {
    await this.authorizer.attemptLogin(email, password, res)
  }

  public checkAuthToken(token: string): number {
    return this.isValidResetQuery(token)
  }

  public async onboard(data: APIOnboardData): Promise<object> {
    const onboarder = new Onboard()
    return onboarder.onboard(data)
  }

  public async canUseInteractions(
    token: string,
    ownerId: number
  ): Promise<boolean> {
    const { userId } = this.authorizer.decodeAuthToken(token)
    if (userId === ownerId || (await this.userIsAdmin(userId))) {
      return true
    }

    let managerId: number = await this.pm.getManagerOfUser(ownerId)
    while (managerId) {
      if (userId === managerId) {
        return true
      }
      // eslint-disable-next-line no-await-in-loop
      const idOfTheManager = await this.pm.getManagerOfUser(managerId)
      if (idOfTheManager === managerId) {
        return false
      }
      managerId = idOfTheManager
    }
    return false
  }

  public async getInteractions(ownerId: number): Promise<APIInteraction[]> {
    const interactions: APIInteraction[] = await this.pm.getInteractionsForUser(
      ownerId
    )
    return interactions.sort((a: APIInteraction, b: APIInteraction) => {
      return b.enteredDateTime - a.enteredDateTime
    })
  }

  private async getManagerOfManagersInteractions(
    managerId: number,
    year: number,
    month: number,
    date: number,
    previousInteractionsYear,
    previousInteractionMonth
  ): Promise<IManagerInteraction[]> {
    const managerList: IManagerList[] = await this.pm.getManagerListUnderUser(
      managerId
    )
    const managerInteractions: IManagerInteraction[] = []

    for (let i = 0; i < managerList.length; i++) {
      const interactions: ICurrentManagerInteractions[] = await this.pm.getTotalInteractionsByMonth(
        managerList[i].id,
        year,
        month,
        date
      )

      if (interactions.length > 0) {
        for (let j = 0; j < interactions.length; j++) {
          managerInteractions.push(
            await this.addManagerInteraction(
              interactions[j],
              managerList[i],
              previousInteractionsYear,
              previousInteractionMonth,
              date
            )
          )
        }
      }
    }
    return managerInteractions
  }

  private async addManagerInteraction(
    interaction: ICurrentManagerInteractions,
    managerList: IManagerList,
    previousInteractionsYear,
    previousInteractionMonth,
    date
  ): Promise<IManagerInteraction> {
    const previousInteraction: IPreviousManagerInteractions = await this.pm.getPreviousInteractions(
      managerList.id,
      previousInteractionsYear,
      previousInteractionMonth,
      date
    )
    return {
      managerName: managerList.name,
      previousInteractions: parseInt(previousInteraction.interactions, 10),
      totalInteractions: parseInt(interaction.interactions, 10),
      isAuthor: !!(interaction.id === managerList.id)
    }
  }

  public async getInteractionsByManagerId(
    managerId: number,
    token: string,
    year: number,
    month: number,
    date: number
  ): Promise<IManagerInteraction[]> {
    const decodedToken: IDecodedAuthToken = this.authorizer.decodeAuthToken(
      token
    )

    if (decodedToken) {
      const previousInteractionsYear = month === 12 ? year - 1 : year
      const previousInteractionMonth = month === 1 ? 12 : month

      const isUserManagerOfManagers = await this.pm.isUserManagerOfManagers(
        managerId
      )

      if (isUserManagerOfManagers) {
        const managerInteractions: IManagerInteraction[] = await this.getManagerOfManagersInteractions(
          managerId,
          year,
          month,
          date,
          previousInteractionsYear,
          previousInteractionMonth
        )
        return managerInteractions
      } else {
        const currentInteractionList: ICurrentManagerInteractions[] = await this.pm.getTotalInteractionsByMonth(
          managerId,
          year,
          month,
          date
        )

        const managerInteractions: IManagerInteraction[] = []
        if (currentInteractionList.length > 0) {
          for (let i = 0; i < currentInteractionList.length; i++) {
            const previousInteraction: IPreviousManagerInteractions = await this.pm.getPreviousInteractions(
              managerId,
              previousInteractionsYear,
              previousInteractionMonth,
              date
            )
            managerInteractions.push({
              managerName: await this.pm.getManagerNameById(managerId),
              previousInteractions: parseInt(
                previousInteraction.interactions,
                10
              ),
              totalInteractions: parseInt(
                currentInteractionList[i].interactions,
                10
              ),
              isAuthor: !!(currentInteractionList[i].id === managerId)
            })
          }
        }
        return managerInteractions
      }
    }
  }

  public async getSFAuth(authToken: string): Promise<object> {
    const decodedAuthToken: IDecodedAuthToken = this.authorizer.decodeAuthToken(
      authToken
    )
    if (decodedAuthToken) {
      const { userId } = decodedAuthToken
      if (await this.userIsManagerOrAdmin(userId)) {
        const companyId = await this.pm.getCompanyIdFromUserId(userId)
        const sfAuth: ISFOAuthInfo = await this.pm.getSFOAuthForCompany(
          companyId
        )
        const { client_id, client_secret, token } = sfAuth
        const grantType = 'refresh_token'
        const format = 'json'
        const url = 'https://login.salesforce.com/services/oauth2/token'

        const body = {
          grant_type: grantType,
          format,
          client_id,
          client_secret,
          refresh_token: token
        }
        return new Promise((res, reject) => {
          req.post({ url, form: body }, (error, _, resBody) => {
            if (error) {
              reject(error)
            }
            if (resBody) {
              res(JSON.parse(resBody))
            }
            res(null)
          })
        })
      }
    }
    return null
  }

  public async resetPassword(
    authToken: string,
    password: string,
    res: express.Response
  ): Promise<void> {
    try {
      await this.authorizer.updatePassword(password, res, authToken)
    } catch (err) {
      Logger.info(`Error resetting password: ${err}`, err)
    }
  }

  public async updatePassword(
    token: string,
    currentPassword: string,
    newPassword: string,
    res: express.Response
  ): Promise<void> {
    try {
      await this.authorizer.regularPasswordReset(
        currentPassword,
        newPassword,
        token,
        res
      )
    } catch (err) {
      Logger.info(`Error resetting password: ${err}`, err)
    }
  }

  public async saveConfiguration(
    token: string,
    configuration: string
  ): Promise<object> {
    const decodedAuth: IDecodedAuthToken = this.authorizer.decodeAuthToken(
      token
    )
    if (decodedAuth !== null) {
      const companyId = await this.pm.getCompanyIdFromUserId(decodedAuth.userId)
      const result = await this.pm.updateConfiguration(configuration, companyId)
      if (result !== null) {
        return { code: OK }
      }
      const code = 2113
      return { code, error: errorCodes[code] }
    }
    const code = 1003
    return { code, error: errorCodes[code] }
  }

  public async recordUsage(
    token: string,
    description: string,
    localTime: string
  ): Promise<void> {
    const decodedAuth: IDecodedAuthToken = this.authorizer.decodeAuthToken(
      token
    )

    if (decodedAuth !== null) {
      const { userId } = decodedAuth
      this.pm.addUsageRecord(description, localTime, userId)
    }
  }

  private isValidResetQuery(token: string): number {
    if (token) {
      return Mailer.decodeAuthToken(token) !== null ? OK : NOT_FOUND
    }
    return null
  }

  public async postLogInteraction(
    authToken: string,
    ownerId: number,
    message: string
  ): Promise<any> {
    const decodedAuthToken: IDecodedAuthToken = this.authorizer.decodeAuthToken(
      authToken
    )
    if (decodedAuthToken !== null) {
      const loggedInteraction: IInteraction[] = await this.pm.logInteraction(
        decodedAuthToken.userId,
        ownerId,
        message
      )
      if (loggedInteraction.length) {
        this.sendLogEmails(loggedInteraction[0], ownerId)
        return { interactions: await this.getInteractions(ownerId) }
      }
      const code = 2115
      return { code, error: errorCodes[code] }
    }
    const code = 1003
    return { code, error: errorCodes[code] }
  }

  private async sendLogEmails(
    log: IInteraction,
    ownerId: number
  ): Promise<void> {
    const creatorNameAndEmail: {
      full_name: string
      email: string
    } = await this.pm.getUserEmailAndNameById(log.created_by_id)
    const ownerNameAndEmail: {
      full_name: string
      email: string
    } = await this.pm.getUserEmailAndNameById(log.owner_id)
    const companyId = await this.pm.getCompanyIdFromUserId(ownerId)
    Mailer.sendLogEmail(log, creatorNameAndEmail, ownerNameAndEmail, companyId)
  }

  public async setUserGoal(
    authToken: string,
    goal: number,
    startDate: string,
    endDate: string
  ): Promise<object> {
    const decodedAuthToken: IDecodedAuthToken = this.authorizer.decodeAuthToken(
      authToken
    )
    if (decodedAuthToken !== null) {
      return this.pm.setUserGoal(decodedAuthToken, goal, startDate, endDate)
    }
    const code = 1003
    return { code, error: errorCodes[code] }
  }

  private async storeFileToAWSs3(
    filename: string,
    ext: string,
    bucket: string
  ): Promise<{ error: any; data: any }> {
    const uploadsFolderLocation = './uploads'

    const body = fs.createReadStream(`${uploadsFolderLocation}/${filename}`)

    const params = {
      Bucket: bucket,
      Key: `${filename}.${ext}`,
      Body: body
    }

    return new Promise((resolve: any): void => {
      this.s3.upload(params, (error: object, data: object): void => {
        if (error) {
          resolve({ error, data: null })
        } else {
          resolve({ error: null, data })
        }
      })
    })
  }

  private async assignProfilePictureToUser(
    userId: number,
    file: IFileMulter,
    ext: string
  ): Promise<void> {
    const image = {
      name: file.filename,
      ext,
      size: file.size,
      type: file.mimetype
    }
    const imageId: number = await this.pm.addProfilePicture(image)
    await this.pm.setUserProfilePicture(imageId, userId)
  }

  public async getTrainings(token: string): Promise<ITraining[] | object> {
    const decodedAuth: IDecodedAuthToken = this.authorizer.decodeAuthToken(
      token
    )
    if (decodedAuth) {
      const trainings: IDBTraining[] =
        (await this.pm.getTrainingsByUserId(decodedAuth.userId)) || []
      return Promise.all(
        trainings.map(async training => {
          let imageSrc = ''
          if (training.thumbnail_id) {
            imageSrc = await this.pm.getImageName(training.thumbnail_id)
          }
          return {
            contentId: training.content_id,
            description: training.description,
            id: training.id,
            name: training.name,
            tags: training.tags,
            imageSrc
          }
        })
      )
    } else {
      const code = 1003
      return {
        code,
        error: errorCodes[code]
      }
    }
  }

  public async uploadTraining(
    token: string,
    trainingContent: IFileMulter,
    trainingThumbnail: IFileMulter,
    trainingName: string,
    trainingDescription: string,
    tags: string
  ): Promise<ITraining | object> {
    const decodeAuthToken: IDecodedAuthToken = this.authorizer.decodeAuthToken(
      token
    )
    if (decodeAuthToken && this.userIsManagerOrAdmin(decodeAuthToken.userId)) {
      const imageFileExtensions = {
        'image/png': 'png',
        'image/jpeg': 'jpg',
        'image/tiff': 'tiff'
      }

      const contentExt = 'pdf'
      const uploadedContent = await this.storeFileToAWSs3(
        trainingContent.filename,
        contentExt,
        process.env.AWS_BUCKET_TRAINING_DOCUMENTS
      )

      const hasThumbnail: boolean = !!trainingThumbnail
      let thumbnailExt = null
      let uploadedThumbnail = null

      if (hasThumbnail) {
        thumbnailExt = imageFileExtensions[trainingThumbnail.mimetype]
        uploadedThumbnail = await this.storeFileToAWSs3(
          trainingThumbnail.filename,
          thumbnailExt,
          process.env.AWS_BUCKET_TRAINING_THUMBNAILS
        )
      }

      if (
        uploadedContent.data &&
        (!hasThumbnail || (hasThumbnail && uploadedThumbnail.data))
      ) {
        const training: ITraining = await this.pm.addNewTraining(
          trainingContent,
          contentExt,
          trainingThumbnail,
          thumbnailExt,
          trainingName,
          trainingDescription,
          tags,
          decodeAuthToken.userId,
          hasThumbnail
        )
        const code = 1047
        return training ? training : { code, error: errorCodes[code] }
      } else {
        const code = 1039
        return {
          code,
          error: errorCodes[code]
        }
      }
    } else {
      const code = 1003
      return {
        code,
        error: errorCodes[code]
      }
    }
  }

  public async uploadProfilePicture(
    token: string,
    file: IFileMulter
  ): Promise<object> {
    const fileExtensions = {
      'image/png': 'png',
      'image/jpeg': 'jpg',
      'image/tiff': 'tiff'
    }
    const ext = fileExtensions[file.mimetype]

    const uploadedData = await this.storeFileToAWSs3(
      file.filename,
      ext,
      process.env.AWS_BUCKET_PROFILE_PICTURES
    )

    if (uploadedData.data) {
      const userId: number = this.getUserIdFromToken(token)
      await this.assignProfilePictureToUser(userId, file, ext)
      return {
        profilePicture: `${file.filename}.${ext}`,
        message: 'Profile picture updated successfully'
      }
    }

    if (uploadedData.error) {
      this.logError(uploadedData.error, 'uploadProfilePicture()')
    }

    const uploadFailCode = 1039
    return this.logAndReturnError(uploadFailCode, 'uploadProfilePicture()')
  }

  public getTrainingThumbnail = async (
    token: string,
    thumbnailId: number,
    res: express.Response
  ): Promise<void> => {
    const decodedToken = this.getDecodedAuth(token)
    if (decodedToken) {
      const key = await this.pm.getImageAWSKey(decodedToken.userId, thumbnailId)
      if (key) {
        const params = {
          Bucket: process.env.AWS_BUCKET_TRAINING_THUMBNAILS,
          Key: key
        }
        this.s3.getObject(
          params,
          (error: { message: string }, data: { Body: object }): void => {
            if (error) {
              this.logError(error.message, 'getTrainingThumbnail()')
              res.send({ error: error.message, data: null })
            } else {
              res.send(data && data.Body)
            }
          }
        )
      } else {
        res.sendStatus(401)
      }
    } else {
      res.sendStatus(401)
    }
  }

  public getTrainingContent = async (
    token: string,
    contentId: number,
    res: express.Response
  ): Promise<void> => {
    const decodedToken = this.getDecodedAuth(token)
    if (decodedToken) {
      const key = await this.pm.getDocumentAWSKey(
        decodedToken.userId,
        contentId
      )
      if (key) {
        const params = {
          Bucket: process.env.AWS_BUCKET_TRAINING_DOCUMENTS,
          Key: key
        }
        this.s3.getObject(
          params,
          (error: { message: string }, data: { Body: object }): void => {
            if (error) {
              this.logError(error.message, 'getTrainingContent()')
              res.send({ error: error.message, data: null })
            } else {
              res.send(
                Object.keys(data.Body).map(key => {
                  return data.Body[key]
                })
              )
            }
          }
        )
      } else {
        res.sendStatus(401)
      }
    } else {
      res.sendStatus(401)
    }
  }

  public getThumbnail(thumbnail: string, res: express.Response): void {
    const params = {
      Bucket: process.env.AWS_BUCKET_TRAINING_THUMBNAILS,
      Key: thumbnail
    }
    this.s3.getObject(
      params,
      (error: { message: string }, data: { Body: object }): void => {
        if (error) {
          this.logError(error.message, 'getThumbnail()')
          res.send({ error: error.message, data: null })
        }
        res.send(data && data.Body)
      }
    )
  }

  public getProfilePicture(
    profilePicture: string,
    res: express.Response
  ): void {
    const params = {
      Bucket: process.env.AWS_BUCKET_PROFILE_PICTURES,
      Key: profilePicture
    }
    this.s3.getObject(
      params,
      (error: { message: string }, data: { Body: object }): void => {
        if (error) {
          this.logError(error.message, 'getProfilePicture()')
          res.send({ error: error.message, data: null })
        }
        res.send(data && data.Body)
      }
    )
  }

  public deleteProfilePicture(token: string): object {
    const userId: number = this.getUserIdFromToken(token)
    this.pm.setUserProfilePicture(null, userId)
    return { message: 'Profile picture successfully deleted' }
  }

  public async getMetrics(token: string): Promise<{ roles: APIMetricRole[] }> {
    const companyId: number = await this.getCompanyIdFromToken(token)
    const roles: APIMetricRole[] = await this.getRolesWithMetrics(companyId)
    return { roles }
  }

  private async getRolesWithMetrics(
    companyId: number
  ): Promise<APIMetricRole[]> {
    const roles: APIRole[] = await this.getRolesByCompanyId(companyId)

    const salesProcess: APIMetric[] = await this.getSkillsOfRoles(companyId)
    const measurableWork: APIMetric[] = await this.getDesiredBehaviorsOfRoles(
      companyId
    )

    return roles.map(
      (role: APIRole): APIMetricRole => ({
        name: role.name,
        salesProcess: salesProcess.filter(
          (metric: APIMetric): boolean => metric.roleId === role.id
        ),
        measurableWork: measurableWork.filter(
          (metric: APIMetric): boolean => metric.roleId === role.id
        )
      })
    )
  }

  private async getRolesByCompanyId(companyId: number): Promise<APIRole[]> {
    const { rolesTable } = this.db
    const roleColumn: string[] = [rolesTable.id, rolesTable.name]
    const roles: APIRole[] = await this.pm.getRolesByCompanyId(
      companyId,
      roleColumn
    )
    return roles.map(
      (object: APIRole): APIRole =>
        StringManipulator.convertObjectPropertiesToCamelCase(object)
    )
  }

  private async getSkillsOfRoles(companyId): Promise<APIMetric[]> {
    const { skillsTable } = this.db
    const skillsColumnToSearch: string[] = [
      skillsTable.benchmark,
      skillsTable.query,
      skillsTable.roleId,
      skillsTable.unit,
      skillsTable.userFacingName,
      skillsTable.stageIndex
    ]
    const skills: APISalesProcessSkill[] = await this.pm.getSkillsOfRolesByCompanyIdOrderByStageIndex(
      companyId,
      skillsColumnToSearch
    )

    return this.convertToMetricsObject(skills)
  }

  private async getDesiredBehaviorsOfRoles(
    companyId: number
  ): Promise<APIMetric[]> {
    const { desiredBehaviorsTable } = this.db
    const desiredBehaviorsColumns: string[] = [
      desiredBehaviorsTable.name,
      desiredBehaviorsTable.query,
      desiredBehaviorsTable.roleId,
      desiredBehaviorsTable.target
    ]

    const desiredBehaviorsObject: APIMeasurableWorkDesiredBehavior[] = await this.pm.getDesiredBehaviorsOfRolesByCompanyId(
      companyId,
      desiredBehaviorsColumns
    )

    return this.convertToMetricsObject(desiredBehaviorsObject)
  }

  private async convertToMetricsObject(
    arrayOfObject: any
  ): Promise<APIMetric[]> {
    return arrayOfObject.map(
      (metric: any): APIMetric => {
        const isASalesProcessMetric = metric.benchmark && !metric.target
        return {
          benchmark: isASalesProcessMetric ? metric.benchmark : metric.target,
          name: isASalesProcessMetric ? metric.userFacingName : metric.name,
          query: typeof metric.query !== 'string' ? '' : metric.query,
          roleId: metric.roleId,
          unit: isASalesProcessMetric ? metric.unit : '',
          stageIndex: metric.stageIndex
        }
      }
    )
  }

  private async getCompanyIdFromToken(token: string): Promise<number> {
    const userId: number = this.getUserIdFromToken(token)
    return this.pm.getCompanyIdFromUserId(userId)
  }

  private getUserIdFromToken(token: string): number {
    const decodedAuth: IDecodedAuthToken = this.getDecodedAuth(token)
    return decodedAuth.userId
  }

  private getDecodedAuth(token: string): IDecodedAuthToken {
    const decodedAuth: IDecodedAuthToken = this.authorizer.decodeAuthToken(
      token
    )
    if (!decodedAuth) {
      const invalidAuthCode = 1003
      throw new Error(errorCodes[invalidAuthCode])
    }
    return decodedAuth
  }

  private logAndReturnError(
    code: number,
    methodName: string
  ): { code: number; error: string } {
    this.logError(errorCodes[code], methodName)
    return { code, error: errorCodes[code] }
  }

  private logError(errorMessage: string, methodName: string): void {
    Logger.info(
      `${APIRouteHandler.name} -> ${methodName}. Error ${errorMessage}`,
      'err'
    )
  }
}

export default APIRouteHandler
