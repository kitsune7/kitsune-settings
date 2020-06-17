import Authorizer from '../Authorizer/Authorizer'
import FactoryPersistenceManager from '../Factories/FactoryPersistenceManager'
import IdName from '../MetricsAPI/Interfaces/IdName'
import IMetric from '../MetricsAPI/Interfaces/IMetric'
import IMetricsAPIAuthorizer from '../MetricsAPI/Interfaces/IMetricsAPIAuthorizer'
import IMetricTarget from '../MetricsAPI/Interfaces/IMetricTarget'
import IPerformance from '../MetricsAPI/Interfaces/IPerformance'
import ITargetPeriodPerformance from '../MetricsAPI/Interfaces/ITargetPeriodPerformance'
import Requester from '../Utilities/Requester'

const baseUrl = 'https://metrics.databased.com'
const metricProfilesEndPoint = '/metricProfiles'
const metricsEndPoint = '/metrics'
const performancesEndPoint = '/performances'
const targetsEndPoint = '/targets'
const termsEndPoint = '/terms'
const usersEndPoint = '/users'

class MetricsAPI {
  private static auth: IMetricsAPIAuthorizer = new Authorizer(
    FactoryPersistenceManager.buildPersistenceManager()
  )

  private static pm = FactoryPersistenceManager.buildPersistenceManager()

  public static async getPerformancesForUserByTargetPeriods(
    userId: number,
    lastNTargetPeriods: number,
    endDate: string,
    metricId: number
  ): Promise<ITargetPeriodPerformance> {
    const queryParams = { lastNTargetPeriods, endDate }
    const queryString = Requester.buildQueryString(queryParams)
    const url = `${baseUrl}${usersEndPoint}/${userId}${metricsEndPoint}/${metricId}${performancesEndPoint}${queryString}`
    const token = this.auth.generateAuthToken('', userId)
    const request = Requester.buildGetRequest(token)
    return Requester.fetch(url, request)
  }

  public static async getPerformancesForUserByLastNWorkdays(
    userId: number,
    lastNWorkdays: number,
    endDate: string
  ): Promise<IPerformance[]> {
    const queryParams = { lastNWorkdays, endDate }
    return this.getPerformances(queryParams, userId)
  }

  public static async getPerformancesForUserByDateRange(
    userId: number,
    startDate: string,
    endDate: string
  ): Promise<IPerformance[]> {
    const queryParams = { startDate, endDate }
    return this.getPerformances(queryParams, userId)
  }

  private static async getPerformances(
    params: object,
    userId: number
  ): Promise<any> {
    const queryString = Requester.buildQueryString(params)
    const url = `${baseUrl}${usersEndPoint}/${userId}${performancesEndPoint}${queryString}`
    const token = this.generateAuthTokenForCommunicatingWithMetricsAPI(userId)
    const request = Requester.buildGetRequest(token)
    return Requester.fetch(url, request)
  }

  public static getPerformancesForUserByWorkDays(
    userId: number,
    lastNWorkdays: number
  ): Promise<IPerformance[]> {
    const queryParams = { lastNWorkdays }
    const queryString = Requester.buildQueryString(queryParams)
    const url = `${baseUrl}${usersEndPoint}/${userId}${performancesEndPoint}${queryString}`
    const token = this.generateAuthTokenForCommunicatingWithMetricsAPI(userId)
    const request = Requester.buildGetRequest(token)
    return Requester.fetch(url, request)
  }

  public static async getMetricProfilesByAuthToken(
    token: string
  ): Promise<IdName[]> {
    const url = `${baseUrl}${metricProfilesEndPoint}`
    const request = Requester.buildGetRequest(token)
    return Requester.fetch(url, request)
  }

  public static async getMetricsByMetricProfileId(
    token: string,
    metricProfileId: number
  ): Promise<any> {
    const url = `${baseUrl}${metricProfilesEndPoint}/${metricProfileId}${metricsEndPoint}`
    const request = Requester.buildGetRequest(token)
    return Requester.fetch(url, request)
  }

  public static async getTermsByMetricProfileId(
    token: any,
    metricProfileId: number
  ): Promise<any> {
    const url = `${baseUrl}${metricProfilesEndPoint}/${metricProfileId}${termsEndPoint}`
    const request = Requester.buildGetRequest(token)
    return Requester.fetch(url, request)
  }

  public static generateAuthTokenForCommunicatingWithMetricsAPI(
    userId: number
  ): string {
    return this.auth.generateAuthToken('', userId)
  }

  public static async getMetricsByMetricProfileIdWithoutToken(
    metricProfileId: number,
    companyId: number
  ): Promise<IMetric[]> {
    const url = `${baseUrl}${metricProfilesEndPoint}/${metricProfileId}${metricsEndPoint}`
    const adminId = await this.pm.getAdminIdForCompany(companyId)
    const token = await this.auth.generateAuthToken('', adminId)
    const request = Requester.buildGetRequest(token)
    return Requester.fetch(url, request)
  }

  public static async getTargetForMetricByDate(
    metricProfileId: number,
    metricId: number,
    startDate: string,
    userId: number,
    numPeriods: number
  ): Promise<IMetricTarget[]> {
    const queryParams = { startDate, numPeriods }
    const queryString = Requester.buildQueryString(queryParams)
    const url = `${baseUrl}${metricProfilesEndPoint}/${metricProfileId}${metricsEndPoint}/${metricId}${targetsEndPoint}${queryString}`
    const token = this.generateAuthTokenForCommunicatingWithMetricsAPI(userId)
    const request = Requester.buildGetRequest(token)
    return Requester.fetch(url, request)
  }
}

export default MetricsAPI
